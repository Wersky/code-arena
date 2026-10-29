shader_type canvas_item;
// 马赛克 → 清晰：终端符号画切回 Godot 时的「对焦」过渡。
//
// 为什么不在 GDScript 里做：逐帧生成缩小图再上传纹理，每帧一次 GPU 上传，卡且费内存。
// 这里是在采样阶段直接把 UV 吸附到块中心，零额外开销，块大小可以从 128 一路到 1。

// 块边长（纹理像素）。1.0 = 不马赛克
uniform float block : hint_range(1.0, 128.0) = 1.0;
// 整体不透明度。用它做淡出，而不是 modulate —— 这样 COLOR 的来源唯一，不会两处相乘
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	float b = max(block, 1.0);

	// 吸附到块中心：块内所有像素拿到同一个采样点
	vec2 snapped = (floor(UV * tex_size / b) + 0.5) * b;
	vec2 block_uv = clamp(snapped * TEXTURE_PIXEL_SIZE, vec2(0.0), vec2(1.0));

	// block 到 1 时块内只剩一个纹素，吸附会变成点采样 → 缩小观看时出现锯齿。
	// 所以用 mix 平滑切回普通 UV 采样（step 当开关，不做分支）。
	vec4 blocked = texture(TEXTURE, block_uv);
	vec4 plain = texture(TEXTURE, UV);
	vec4 c = mix(blocked, plain, step(b, 1.001));

	c.a *= alpha;
	COLOR = c;
}
