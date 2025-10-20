# Uncomment if you want to use validation for your Events
#extends EventBridgeManager

# === Validators ===
# These methods automatically protect events by name.
#
#func validate_YOUR_EVENT(arg1,arg2,etc) -> bool:
	#if DEBUG:
		#print("[VALIDATOR] Checking YOUR_EVENT %s %s %s:" % [arg1,arg2,etc])
		### or use the custom logger
		##EventBridgeLogger.event_log(str(self), "Checking dice_result: %d" % result, 3)
	###true or false must be the return
	#return true
