#version 330 compatibility

#include "/lib/common.glsl"

uniform sampler2D lightmap;
uniform sampler2D gtexture;
uniform sampler2D shadowtex0;

uniform float alphaTestRef = 0.1;

in vec2 lmcoord;
in vec2 texcoord;
in vec4 glcolor;
in vec3 vNormal;
in vec4 shadowPos;

/* RENDERTARGETS: 0,1 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 normalData;

void main() {
    vec4 texColor = texture(gtexture, texcoord) * glcolor;
    if (texColor.a < alphaTestRef) {
        discard;
    }

    vec3 N = normalize(vNormal);
    vec3 L = getLightDirection();
    vec3 V = normalize(-vNormal);
    
    // --- STAGE 3: SHADOW MODEL ---
    float shadowVisibility = getShadow(shadowPos, shadowtex0);

    // --- STAGE 1: LIGHTING MODEL (CEL SHADING) ---
    vec3 litColor = applyCelLighting(texColor.rgb, N, L, V, shadowVisibility);
    
    // Add a slight blue tint for water stylization if it's very transparent
    if (texColor.a < 0.5) {
        litColor = mix(litColor, vec3(0.4, 0.6, 0.9), 0.3);
    }
    
    vec4 light = texture(lightmap, lmcoord);
    color = vec4(litColor * clampLightmap(light.rgb), texColor.a);
    
    normalData = vec4(N * 0.5 + 0.5, 1.0);
}
