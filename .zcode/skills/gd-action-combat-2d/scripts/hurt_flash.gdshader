shader_type canvas_item;
// 受击闪白。挂在角色 Sprite2D 的 material 上，脚本驱动 flash_amount。
// 脚本侧：
//   func hurt_flash():  sprite.material.set_shader_parameter("flash_amount",
//                          sin(float(Time.get_ticks_msec()) / 40) * 0.5 + 0.5)
//   func reset_flash(): sprite.material.set_shader_parameter("flash_amount", 0)
//   _process 里: if hurt_timer.is_stopped(): return; hurt_flash()
// （与无敌帧共用同一个 Timer，不要第二套计时器）

uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec4 texture_color = texture(TEXTURE, UV);
	// 乘 alpha 保证透明像素不被染白
	COLOR = mix(texture_color, flash_color, flash_amount * texture_color.a);
}
