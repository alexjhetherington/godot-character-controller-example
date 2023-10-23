# godot-character-controller-example
An example implementation of a character controller, using move_and_collide. Created with Godot 4.1.

This repository is *not* meant to be a drag-and-drop character controller for Godot. The main purpose is to demonstrate how a character controller can be created using move_and_collide, because there's so little about that on the internet. That being said, check out the limitations below; and feel free to do whatever you need to do to include it in your game. If you find it helpful, please let me know!

## Motivation
See my Manifesto! It contains further explanation for what and why this exists! http://www.footnotesforthefuture.com/words/godot-movement-manifesto/

## Limitations and Considerations
* ***IMPORTANT*** Godot Jolt is absolutely mandatory for any physics queries not using box shapes (this uses a cylinder shape): https://github.com/godot-jolt/godot-jolt
* I roughly copy and pasted the code from my main project. This means:
  * There may be broken references if you try to actually use this code (in the scene, input, code etc)
  * Movement is for my project! For example, there is no jumping; no momentum etc.
  * I combined classes to make the project easier to share; separation of concerns is not a thing in this demo!
* I will accept PRs to help make this a more complete demo, but I won't discuss getting this to work in your project unless you very obviously know what you're talking about, sorry!

## Required Input Map
	move_forward
	move_backward
	strafe_left
	strafe_right
	sprint
	(escape key will free mouse)
	
