#version 330 compatibility

#include "/lib/common.glsl"

uniform sampler2D lightmap;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
	vec3 lm = clampLightmap(texture(lightmap, lmcoord).rgb);
	color = vec4(glcolor.rgb * lm, glcolor.a);
	if (color.a < alphaTestRef) {
		discard;
	}
}
