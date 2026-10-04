@abstract
extends RefCounted
class_name MultiWorldLog

## Logging hook for the multi-world addon.
##
## The addon is silent by default. Route its messages into your own logger by assigning
## [member sink], or set [member enabled] to print them with a plain `print()`.

## Optional `func(message: String) -> void`. When valid, every log message is passed to it.
static var sink: Callable

## If true and no [member sink] is set, messages are printed to the output.
static var enabled: bool = false


static func log(message: String) -> void:
	if sink:
		sink.call(message)
	elif enabled:
		print("[MultiWorld] ", message)
