# Stały adres lokalnego resolvera zapobiega używaniu publicznych resolverów,
# które często ograniczają zapytania do list RBL.
dns {
  nameserver = ["192.0.2.53:53"];
  timeout = 2s;
  retransmits = 2;
  sockets = 16;
}

# Skan ma zakończyć się jednoznacznym wynikiem zamiast zawieszać cały przebieg.
task_timeout = 15s;
# Odpowiedź "soft reject" jest przez Guardiana zawsze traktowana jako
# nieukończony skan i nigdy nie daje prawa do automatycznego ruchu ani purge.
soft_reject_on_timeout = true;
