shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform bool is_active = false;

void fragment() {
	vec4 original_color = texture(screen_texture, SCREEN_UV);
	
	if (!is_active) {
		COLOR = original_color;
	} else {
		float r = original_color.r;
		float g = original_color.g;
		float b = original_color.b;
		
		float r_shift = max(0.0, r - g) * 3.5; 
		float g_shift = max(0.0, g - r) * 3.5;
		
		vec3 corrected_color = vec3(r, g, b + r_shift + g_shift);
		
		COLOR = vec4(corrected_color, original_color.a);
	}
}