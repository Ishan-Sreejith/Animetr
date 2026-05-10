#version 330 compatibility

uniform int renderStage;
uniform float viewHeight;
uniform float viewWidth;
uniform mat4 gbufferModelView;
uniform mat4 gbufferProjectionInverse;
uniform vec3 fogColor;
uniform vec3 skyColor;

in vec4 glcolor;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

vec3 screenToView(vec3 screenPos) {
    vec3 ndcPos = screenPos * 2.0 - 1.0;
    vec4 tmp = gbufferProjectionInverse * vec4(ndcPos, 1.0);
    return tmp.xyz / tmp.w;
}

void main() {
    if (renderStage == 32) { // stars (MC_RENDER_STAGE_STARS)
        color = glcolor;
    } else {
        vec3 pos = screenToView(vec3(gl_FragCoord.xy / vec2(viewWidth, viewHeight), 1.0));
        vec3 V = normalize(pos);
        float upDot = dot(V, gbufferModelView[1].xyz);
        
        // --- SKY STYLIZATION ---
        // Create a cleaner, more vibrant anime gradient
        vec3 topColor = skyColor * 1.2;
        vec3 bottomColor = fogColor;
        
        vec3 finalSky = mix(bottomColor, topColor, smoothstep(-0.1, 0.5, upDot));
        
        color = vec4(finalSky, 1.0);
    }
}
