class_name State extends Node
## 状态基类。状态就是子节点，change_state 用节点名寻址。
## 用法：SubStateMachine 也 extends State，所以"子状态机"能当状态用（层级状态机的关键）。

signal change(target: String)

func enter() -> void:
	pass

func exit() -> void:
	pass

func tick(_delta: float) -> void:
	pass

func change_to(target: String) -> void:
	change.emit(target)
