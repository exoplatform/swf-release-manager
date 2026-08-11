#!/bin/bash
GPG_MAJOR_VERSION=$(/usr/bin/gpg --version 2>/dev/null | sed -n '1s/.* \([0-9]\+\)\..*/\1/p')
if [ "${GPG_MAJOR_VERSION}" -ge "2" ]; then
    /usr/bin/gpg --batch --pinentry-mode=loopback --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
else 
    /usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
fi
# Initialize trustdb
/usr/bin/gpg --list-keys &>/dev/null