#!/usr/bin/expect -f
spawn ssh-add ~/.ssh/id_release
expect "Enter passphrase"
send "$::env(SSH_PASS)\r"
expect eof
