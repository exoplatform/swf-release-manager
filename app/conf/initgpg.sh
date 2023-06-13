#!/bin/bash
OS_MAJOR_VERSION=$(/usr/bin/lsb_release -sr | cut -d '.' -f 1)
if [ "${OS_MAJOR_VERSION}" -ge "18" ]; then 
    /usr/bin/gpg --batch --pinentry-mode=loopback --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
else 
    /usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import $HOME/.gpg.key &>/dev/null
fi
# Initialize trustdb
/usr/bin/gpg --list-keys &>/dev/null