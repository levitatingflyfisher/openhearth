# vectors

Test vectors that pin the wire format. The Python scripts build every byte by hand and sign with an independent library (pyca or PyNaCl), so the Rust kernel, both relays and the Dart package are checked against bytes none of them made. The JSON files are the output. The tests in `kernel/`, `relay/`, `go-relay/` and `flutter/hearth_sync/` read them. Change the script first, regenerate the JSON, then change the code (see `AGENTS.md`).
