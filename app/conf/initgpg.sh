#!/bin/bash
GPG_VERSION=$(/usr/bin/gpg --version 2>&1 | awk 'NR==1{print $NF}')
if [ "${GPG_VERSION%%.*}" -ge "2" ]; then 
    /usr/bin/gpg --batch --pinentry-mode=loopback --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
else 
    /usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
fi
# Initialize trustdb
/usr/bin/gpg --list-keys &>/dev/null