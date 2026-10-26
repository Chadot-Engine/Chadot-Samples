
/*      Cinematic Post-Processing Shader v1.4       */
/*            Developed by Hamid.Memar              */
/*      License : Creative Commons (CC) BY 4.0      */

shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture;
uniform sampler2D grain_texture;

uniform float ca_intensity = 0.002;
uniform float vignette_intensity = 0.6;
uniform float vignette_smoothness = 0.7;
uniform float grain_fps = 60.0;
uniform float grain_scale = 1.0;
uniform float grain_intensity = 0.05;
uniform float grain_dark_point = 0.3;
uniform float grain_dark_intensity = 2.0;
uniform float clarity_intensity = 0.25;
uniform float clarity_radius = 3.0;
uniform vec4 lens_distortion = vec4(0.1, 0.4, 0.0, 0.0);

// Helpers & Effects
float random(float x) { return fract(sin(x) * 43758.5453); }
vec3 chromatic_aberration(vec2 uv)
{
	vec2 center = vec2(0.5, 0.5);
	vec2 dir_from_center = normalize(uv - center);
	
	const int samples = 12;
	vec3 final_color = vec3(0.0);
	vec3 total_weight = vec3(0.0);
	
	for (int i = 0; i < samples; i++)
	{
		float t = float(i) / float(samples - 1);
		float wavelength = mix(400.0, 700.0, t);
		
		float t_norm = (wavelength - 400.0) / 300.0;
		float dispersion = pow(1.0 - t_norm, 1.2);
		float offset_amount = (dispersion - 0.5) * ca_intensity * 2.0;
		vec2 uv_offset = dir_from_center * offset_amount;
		
		vec3 sample_color = texture(SCREEN_TEXTURE, uv + uv_offset).rgb;
		
		vec3 wavelength_color = vec3(0.0);
		if (wavelength >= 380.0 && wavelength < 440.0)
		{
			wavelength_color.r = -(wavelength - 440.0) / (440.0 - 380.0);
			wavelength_color.b = 1.0;
		} else if (wavelength >= 440.0 && wavelength < 490.0)
		{
			wavelength_color.g = (wavelength - 440.0) / (490.0 - 440.0);
			wavelength_color.b = 1.0;
		} else if (wavelength >= 490.0 && wavelength < 510.0)
		{
			wavelength_color.g = 1.0;
			wavelength_color.b = -(wavelength - 510.0) / (510.0 - 490.0);
		} else if (wavelength >= 510.0 && wavelength < 580.0)
		{
			wavelength_color.r = (wavelength - 510.0) / (580.0 - 510.0);
			wavelength_color.g = 1.0;
		} else if (wavelength >= 580.0 && wavelength < 645.0)
		{
			wavelength_color.r = 1.0;
			wavelength_color.g = -(wavelength - 645.0) / (645.0 - 580.0);
		} else if (wavelength >= 645.0 && wavelength <= 700.0)
		{
			wavelength_color.r = 1.0;
		}
		
		final_color += sample_color * wavelength_color;
		total_weight += wavelength_color;
	}
	
	return final_color / max(total_weight, vec3(0.001));
}
vec3 vignette(vec3 color, vec2 uv)
{
	vec2 vig_uv = uv * 2.0 - 1.0;
	float dist = length(vig_uv);
	float vignette = 1.0 - (smoothstep(0.0, vignette_smoothness, dist) * vignette_intensity);
	return color * vignette;
}
vec3 grain(vec3 color, vec2 uv, vec2 screen_size)
{
	vec2 grain_uv = uv * grain_scale;
	grain_uv.x = fract(grain_uv.x * (screen_size.y / screen_size.x));
	float frame = floor(TIME * grain_fps);
	vec2 random_offset = vec2(random(frame), random(frame + 1.0));
	grain_uv = fract(grain_uv + random_offset);
	vec3 grain_sample = texture(grain_texture, grain_uv).rgb;
	float luminance = (color.r + color.g + color.b) / 3.0;
	float dark_factor = max(0.0, grain_dark_point - luminance);
	dark_factor = pow(dark_factor / grain_dark_point, 2.0);
	float intensity = grain_intensity * (1.0 + dark_factor * grain_dark_intensity);
	return color + (grain_sample * intensity);
}
vec3 high_pass_clarity(vec3 color, vec2 uv, vec2 texel_size)
{
	vec3 blurred = vec3(0.0);
	float total_weight = 0.0;
	for (float x = -clarity_radius; x <= clarity_radius; x += 1.0)
	{
		for (float y = -clarity_radius; y <= clarity_radius; y += 1.0)
		{
			vec2 offset = vec2(x, y) * texel_size;
			float dist = length(vec2(x, y)) / clarity_radius;
			float weight = 1.0 - smoothstep(0.0, 1.0, dist);
			blurred += texture(SCREEN_TEXTURE, uv + offset).rgb * weight;
			total_weight += weight;
		}
	}
	blurred /= total_weight;
	vec3 high_pass = color - blurred;
	float luminance = dot(color, vec3(0.299, 0.587, 0.114));
	float strength = clarity_intensity * (0.5 + pow(luminance, 0.7) * 0.5);
	return color + high_pass * strength;
}
vec2 barrel_lens_distortion(vec2 uv)
{
	vec2 r0_xy = -1.0 + uv.yx;
	r0_xy = r0_xy * uv.yx;
	r0_xy = r0_xy * lens_distortion.yx;
	vec2 r0_zw = -0.5 + uv.xy;
	r0_xy = r0_xy * r0_zw + uv.xy;
	return r0_xy;
}

// Post-Processor
void fragment()
{
	vec2 distorted_uv = barrel_lens_distortion(SCREEN_UV);
	vec3 color = chromatic_aberration(distorted_uv);
	color = high_pass_clarity(color, distorted_uv, SCREEN_PIXEL_SIZE);
	color = vignette(color, distorted_uv);
	color = grain(color, distorted_uv, SCREEN_PIXEL_SIZE);
	COLOR = vec4(color, 1.0);
}
