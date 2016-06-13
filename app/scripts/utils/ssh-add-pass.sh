#!/usr/bin/expect -f
spawn ssh-add
expect "Enter passphrase"
send "$::env(SSH_PASS)\r"
expect eof
