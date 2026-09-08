package imapmail

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"slices"
	"strings"
	"sync"
	"time"

	"github.com/emersion/go-imap/v2"
	"github.com/emersion/go-imap/v2/imapclient"
)

type Client struct {
	client      *imapclient.Client
	account     string
	selected    string
	uidValidity uint32
	uidNext     uint32
	done        chan struct{}
	closeOnce   sync.Once
}

type Mailbox struct {
	Name       string
	Delimiter  rune
	Attributes []string
	IsJunk     bool
}

type Capabilities struct {
	Move      bool
	UIDPlus   bool
	IMAP4rev2 bool
	Names     []string
}

type Message struct {
	Folder       string
	UIDValidity  uint32
	UID          uint32
	Size         int64
	MessageID    string
	InternalDate time.Time
	Flags        []string
	Raw          []byte
}

type MoveResult struct {
	UIDValidity uint32
	UID         uint32
}

var (
	ErrAuthentication     = errors.New("o2 odrzuciło dane logowania IMAP")
	ErrUIDValidityChanged = errors.New("UIDVALIDITY folderu zmieniło się; operacja według UID została zablokowana")
)

func Dial(ctx context.Context, host string, port int, account, password string) (*Client, error) {
	return dialWithTLSConfig(ctx, host, port, account, password, &tls.Config{
		ServerName: host,
		MinVersion: tls.VersionTLS12,
	})
}

func dialWithTLSConfig(ctx context.Context, host string, port int, account, password string, tlsConfig *tls.Config) (*Client, error) {
	if host == "" || port < 1 || account == "" || password == "" {
		return nil, errors.New("niepełne dane połączenia IMAP")
	}
	address := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	c, err := imapclient.DialTLS(address, &imapclient.Options{
		TLSConfig: tlsConfig,
		Dialer:    &net.Dialer{Timeout: 15 * time.Second, KeepAlive: 30 * time.Second},
	})
	if err != nil {
		return nil, fmt.Errorf("połączenie TLS z %s: %w", address, err)
	}
	out := &Client{client: c, account: account, done: make(chan struct{})}
	go func() {
		select {
		case <-ctx.Done():
			out.abort()
		case <-out.done:
		}
	}()
	if err := c.Login(account, password).Wait(); err != nil {
		_ = out.Close()
		return nil, fmt.Errorf("%w: %v", ErrAuthentication, err)
	}
	return out, nil
}

func (c *Client) Close() error {
	var err error
	c.closeOnce.Do(func() {
		close(c.done)
		err = c.client.Logout().Wait()
		_ = c.client.Close()
	})
	return err
}

func (c *Client) abort() {
	c.closeOnce.Do(func() {
		close(c.done)
		_ = c.client.Close()
	})
}

func (c *Client) Capabilities() Capabilities {
	caps := c.client.Caps()
	var names []string
	for capName := range caps {
		names = append(names, string(capName))
	}
	slices.Sort(names)
	return Capabilities{
		Move:      caps.Has(imap.CapMove),
		UIDPlus:   caps.Has(imap.CapUIDPlus),
		IMAP4rev2: caps.Has(imap.CapIMAP4rev2),
		Names:     names,
	}
}

func (c *Client) SafeMoveSupported() bool {
	return safeMoveSupported(c.Capabilities())
}

func safeMoveSupported(caps Capabilities) bool {
	// Fail closed: UIDPLUS alone would make go-imap emulate MOVE with COPY,
	// STORE \Deleted and UID EXPUNGE. Guardian permits moves only when the
	// server advertises native MOVE (directly or as part of IMAP4rev2).
	return caps.Move || caps.IMAP4rev2
}

func (c *Client) SafeDeleteSupported() bool {
	return c.Capabilities().UIDPlus
}

func (c *Client) ListMailboxes() ([]Mailbox, error) {
	cmd := c.client.List("", "*", nil)
	data, err := cmd.Collect()
	if err != nil {
		return nil, fmt.Errorf("lista folderów IMAP: %w", err)
	}
	out := make([]Mailbox, 0, len(data))
	for _, item := range data {
		m := Mailbox{Name: item.Mailbox, Delimiter: item.Delim}
		for _, attr := range item.Attrs {
			m.Attributes = append(m.Attributes, string(attr))
			if attr == imap.MailboxAttrJunk {
				m.IsJunk = true
			}
		}
		out = append(out, m)
	}
	slices.SortFunc(out, func(a, b Mailbox) int {
		return strings.Compare(strings.ToLower(a.Name), strings.ToLower(b.Name))
	})
	return out, nil
}

func DetectSpamFolder(mailboxes []Mailbox) string {
	for _, box := range mailboxes {
		if box.IsJunk {
			return box.Name
		}
	}
	candidates := []string{"spam", "junk", "niechciane", "wiadomości-śmieci", "wiadomosci-smieci"}
	for _, wanted := range candidates {
		for _, box := range mailboxes {
			name := strings.ToLower(strings.TrimSpace(box.Name))
			if name == wanted || strings.HasSuffix(name, "/"+wanted) || strings.HasSuffix(name, "."+wanted) {
				return box.Name
			}
		}
	}
	return ""
}

func (c *Client) EnsureMailboxes(names ...string) error {
	existing, err := c.ListMailboxes()
	if err != nil {
		return err
	}
	seen := make(map[string]bool, len(existing))
	folded := make(map[string]string, len(existing))
	for _, box := range existing {
		seen[box.Name] = true
		folded[strings.ToLower(box.Name)] = box.Name
	}
	for _, name := range names {
		if seen[name] {
			continue
		}
		if conflict, ok := folded[strings.ToLower(name)]; ok {
			return fmt.Errorf(
				"folder %q różni się od wymaganej nazwy %q tylko wielkością liter; zmień jego nazwę przed uruchomieniem Guardiana",
				conflict,
				name,
			)
		}
		if err := c.client.Create(name, nil).Wait(); err != nil {
			return fmt.Errorf("tworzenie folderu %q: %w", name, err)
		}
		seen[name] = true
		folded[strings.ToLower(name)] = name
	}
	return nil
}

func (c *Client) SearchSince(folder string, since time.Time, limit int) ([]uint32, uint32, error) {
	uidValidity, err := c.selectFolderFresh(folder, true)
	if err != nil {
		return nil, 0, err
	}
	criteria := &imap.SearchCriteria{}
	if !since.IsZero() {
		criteria.Since = since
	}
	data, err := c.client.UIDSearch(criteria, nil).Wait()
	if err != nil {
		return nil, 0, fmt.Errorf("wyszukiwanie w folderze %q: %w", folder, err)
	}
	uids := data.AllUIDs()
	out := make([]uint32, len(uids))
	for i, uid := range uids {
		out[i] = uint32(uid)
	}
	slices.Sort(out)
	if limit > 0 && len(out) > limit {
		out = out[len(out)-limit:]
	}
	return out, uidValidity, nil
}

// SearchUIDPage searches a bounded numeric UID range strictly above afterUID.
// The server therefore never needs to return an unbounded folder-wide result.
func (c *Client) SearchUIDPage(folder string, afterUID uint32, limit int) ([]uint32, uint32, bool, error) {
	if limit < 1 || limit > 1000 {
		return nil, 0, false, errors.New("rozmiar strony UID musi mieścić się między 1 a 1000")
	}
	uidValidity, err := c.selectFolder(folder, true)
	if err != nil {
		return nil, 0, false, err
	}
	start := afterUID + 1
	if start == 0 || c.uidNext == 0 {
		return nil, uidValidity, true, nil
	}
	lastUID := c.uidNext - 1
	if start > lastUID {
		return nil, uidValidity, true, nil
	}
	end := start + uint32(limit) - 1
	if end < start || end > lastUID {
		end = lastUID
	}
	uidSet := imap.UIDSet{}
	uidSet.AddRange(imap.UID(start), imap.UID(end))
	data, err := c.client.UIDSearch(&imap.SearchCriteria{UID: []imap.UIDSet{uidSet}}, nil).Wait()
	if err != nil {
		return nil, 0, false, fmt.Errorf("stronicowane wyszukiwanie w folderze %q: %w", folder, err)
	}
	uids := data.AllUIDs()
	out := make([]uint32, len(uids))
	for i, uid := range uids {
		out[i] = uint32(uid)
	}
	slices.Sort(out)
	complete := end >= lastUID
	return out, uidValidity, complete, nil
}

func (c *Client) Fetch(folder string, uid uint32, withRaw bool) (Message, error) {
	uidValidity, err := c.selectFolder(folder, true)
	if err != nil {
		return Message{}, err
	}
	options := &imap.FetchOptions{
		UID: true, Envelope: true, Flags: true, InternalDate: true, RFC822Size: true,
	}
	if withRaw {
		options.BodySection = []*imap.FetchItemBodySection{{Peek: true}}
	}
	items, err := c.client.Fetch(imap.UIDSetNum(imap.UID(uid)), options).Collect()
	if err != nil {
		return Message{}, fmt.Errorf("pobieranie UID %d z %q: %w", uid, folder, err)
	}
	if len(items) != 1 {
		return Message{}, fmt.Errorf("wiadomość UID %d zniknęła z folderu %q", uid, folder)
	}
	item := items[0]
	msg := Message{
		Folder: folder, UIDValidity: uidValidity, UID: uint32(item.UID),
		Size: item.RFC822Size, InternalDate: item.InternalDate,
	}
	if item.Envelope != nil {
		msg.MessageID = item.Envelope.MessageID
	}
	for _, flag := range item.Flags {
		msg.Flags = append(msg.Flags, string(flag))
	}
	if withRaw {
		if len(item.BodySection) != 1 {
			return Message{}, fmt.Errorf("serwer nie zwrócił pełnej treści UID %d", uid)
		}
		msg.Raw = item.BodySection[0].Bytes
	}
	return msg, nil
}

func (c *Client) Move(folder string, expectedUIDValidity, uid uint32, destination string, markUnread bool) (MoveResult, error) {
	if !c.SafeMoveSupported() {
		return MoveResult{}, errors.New("serwer nie obsługuje natywnego IMAP MOVE; przenoszenie zablokowane")
	}
	uidValidity, err := c.selectFolder(folder, false)
	if err != nil {
		return MoveResult{}, err
	}
	if err := requireUIDValidity(folder, expectedUIDValidity, uidValidity); err != nil {
		return MoveResult{}, err
	}
	data, err := c.client.Move(imap.UIDSetNum(imap.UID(uid)), destination).Wait()
	if err != nil {
		return MoveResult{}, fmt.Errorf("przenoszenie UID %d z %q do %q: %w", uid, folder, destination, err)
	}
	result := MoveResult{UIDValidity: data.UIDValidity}
	if uids, ok := data.DestUIDs.(imap.UIDSet); ok {
		nums, complete := uids.Nums()
		if complete && len(nums) == 1 {
			result.UID = uint32(nums[0])
		}
	}
	c.selected = folder
	if markUnread && result.UID > 0 {
		if err := c.MarkUnread(destination, result.UIDValidity, result.UID); err != nil {
			return result, err
		}
	}
	return result, nil
}

func (c *Client) MarkUnread(folder string, expectedUIDValidity, uid uint32) error {
	uidValidity, err := c.selectFolder(folder, false)
	if err != nil {
		return err
	}
	if err := requireUIDValidity(folder, expectedUIDValidity, uidValidity); err != nil {
		return err
	}
	cmd := c.client.Store(imap.UIDSetNum(imap.UID(uid)), &imap.StoreFlags{
		Op: imap.StoreFlagsDel, Silent: true, Flags: []imap.Flag{imap.FlagSeen},
	}, nil)
	if err := cmd.Close(); err != nil {
		return fmt.Errorf("oznaczanie odzyskanej wiadomości jako nieprzeczytanej: %w", err)
	}
	return nil
}

func (c *Client) AppendUnread(folder string, raw []byte, internalDate time.Time) (MoveResult, error) {
	if len(raw) == 0 {
		return MoveResult{}, errors.New("nie można przywrócić pustej wiadomości")
	}
	if internalDate.IsZero() {
		internalDate = time.Now()
	}
	cmd := c.client.Append(folder, int64(len(raw)), &imap.AppendOptions{Time: internalDate})
	if _, err := cmd.Write(raw); err != nil {
		return MoveResult{}, err
	}
	if err := cmd.Close(); err != nil {
		return MoveResult{}, err
	}
	data, err := cmd.Wait()
	if err != nil {
		return MoveResult{}, fmt.Errorf("przywracanie wiadomości do %q: %w", folder, err)
	}
	return MoveResult{UIDValidity: data.UIDValidity, UID: uint32(data.UID)}, nil
}

func (c *Client) DeleteUID(folder string, expectedUIDValidity, uid uint32) error {
	if !c.SafeDeleteSupported() {
		return errors.New("serwer nie obsługuje UIDPLUS; trwałe kasowanie zablokowane")
	}
	uidValidity, err := c.selectFolder(folder, false)
	if err != nil {
		return err
	}
	if err := requireUIDValidity(folder, expectedUIDValidity, uidValidity); err != nil {
		return err
	}
	cmd := c.client.Store(imap.UIDSetNum(imap.UID(uid)), &imap.StoreFlags{
		Op: imap.StoreFlagsAdd, Silent: true, Flags: []imap.Flag{imap.FlagDeleted},
	}, nil)
	if err := cmd.Close(); err != nil {
		return err
	}
	// STORE and UID EXPUNGE are separate UID mutations. Re-select and compare
	// the generation again immediately before the irreversible second command;
	// the mailbox may have been rebuilt while the STORE response was in flight.
	uidValidity, err = c.selectFolderFresh(folder, false)
	if err != nil {
		return err
	}
	if err := requireUIDValidity(folder, expectedUIDValidity, uidValidity); err != nil {
		return err
	}
	if err := c.client.UIDExpunge(imap.UIDSetNum(imap.UID(uid))).Close(); err != nil {
		rollback := c.client.Store(imap.UIDSetNum(imap.UID(uid)), &imap.StoreFlags{
			Op: imap.StoreFlagsDel, Silent: true, Flags: []imap.Flag{imap.FlagDeleted},
		}, nil)
		if rollbackErr := rollback.Close(); rollbackErr != nil {
			return fmt.Errorf(
				"UID EXPUNGE %d w %q nie zostało jednoznacznie potwierdzone (%v), a cofnięcie flagi \\\\Deleted także się nie udało: %w",
				uid, folder, err, rollbackErr,
			)
		}
		return fmt.Errorf(
			"UID EXPUNGE %d w %q nie powiodło się; flaga \\\\Deleted została cofnięta: %w",
			uid, folder, err,
		)
	}
	return nil
}

func requireUIDValidity(folder string, expected, actual uint32) error {
	if expected == 0 || actual == 0 || expected != actual {
		return fmt.Errorf("%w: folder %q, oczekiwano %d, serwer zgłosił %d", ErrUIDValidityChanged, folder, expected, actual)
	}
	return nil
}

func (c *Client) selectFolder(folder string, readOnly bool) (uint32, error) {
	if c.selected == folder && c.uidValidity != 0 {
		// A read-write selection also satisfies a read-only request.
		if readOnly {
			return c.uidValidity, nil
		}
		// Select again because we do not track whether the existing selection is read-only.
	}
	return c.selectFolderFresh(folder, readOnly)
}

func (c *Client) selectFolderFresh(folder string, readOnly bool) (uint32, error) {
	data, err := c.client.Select(folder, &imap.SelectOptions{ReadOnly: readOnly}).Wait()
	if err != nil {
		return 0, fmt.Errorf("otwieranie folderu %q: %w", folder, err)
	}
	c.selected = folder
	c.uidValidity = data.UIDValidity
	c.uidNext = uint32(data.UIDNext)
	return data.UIDValidity, nil
}
