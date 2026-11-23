##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2026 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

# Joins a command's arguments into text that follows the command in a container's
# `cmd /s /c` string.
#
# That string reaches the container through docker.exe, which escapes every
# embedded double quote with a backslash. `cmd /s /c` removes only the outer pair
# of quotes and leaves the backslashes, so a quoted argument arrives with literal
# quote characters in it: `swift test "-Xswiftc"` hands swift the argument
# `"-Xswiftc"`. No quoting survives that path, so an argument has to need none.
# One that does is refused, because passing it on would run the command with a
# different argument than the caller wrote. That is an empty argument, one with
# whitespace, a non-ASCII or control character (including a newline), or one of
# the characters cmd acts on: " % & < > ^ |
function Format-ContainerCommandArguments([string[]]$Arguments) {
    $formatted = foreach ($argument in $Arguments) {
        # \z, not $: in .NET $ also matches before a trailing newline.
        if ($argument -notmatch '\A[\x21-\x7E]+\z' -or $argument -match '["%&<>^|]') {
            throw "The argument '$argument' cannot be passed to a command run in a container: it is empty, or holds whitespace, a non-ASCII or control character, or one of the characters cmd acts on (`" % & < > ^ |). Put the command and its arguments in the command itself."
        }
        $argument
    }

    return $formatted -join ' '
}
