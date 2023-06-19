#!/bin/bash
GPG_VERSION=$(/usr/bin/gpg --version 2>&1 | awk 'NR==1{print $NF}')
if [ "${GPG_VERSION%%.*}" -ge "2" ]; then 
    /usr/bin/gpg --batch --pinentry-mode=loopback --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes "$@"
else 
    /usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes "$@"
fi
