class_name DriveInput
extends RefCounted
## One frame of driver intent, whichever device it came from.

var throttle := 0.0
var brake := 0.0
var steer := 0.0
var has_target := false  ## Stick and touch: "point where you want to go".
var target_heading := 0.0
var horn := false
