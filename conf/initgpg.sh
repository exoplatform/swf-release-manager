#!/bin/bash
GPG_VERSION=$(/usr/bin/gpg --version 2>&1 | head -1 | grep -oP '\d+\.\d+' | head -1 | cut -d. -f1)
if [ "${GPG_VERSION}" -ge "2" ]; then
    /usr/bin/gpg --batch --pinentry-mode=loopback --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import "${HOME}/.gpg.key" 2>/dev/null
else
    /usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes --import "${HOME}/.gpg.key" 2>/dev/null
fi
/usr/bin/gpg --list-keys 2>/dev/null
