#!/usr/bin/expect -f
spawn ssh-add
expect "Enter passphrase"
send "$::env(github_ssh_passphrase)\r"
expect eof
