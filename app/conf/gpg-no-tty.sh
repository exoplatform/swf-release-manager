#!/bin/bash
/usr/bin/gpg --batch --no-tty --passphrase "@@GPG_KEY_PASSPHRASE@@" --trust-model always --yes "$@"