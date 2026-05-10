#version 330 compatibility

#include "/lib/common.glsl"

uniform sampler2D colortex0;
uniform sampler2D colortex1;
uniform sampler2D depthtex0;

uniform float viewWidth;
uniform float viewHeight;
uniform float outlineThickness;
uniform int debugMode; // 0=normal,1=edge,2=baseColor,3=depth

// -- PARAMETERS ARE NOW IN lib/common.glsl --

in vec2 texcoord;

/* RENDERTARGETS: 0 */
layout(location = 0) out vec4 color;

void main() {
    vec3 baseColor = texture(colortex0, texcoord).rgb;
    float depth = texture(depthtex0, texcoord).r;
    vec3 normal = texture(colortex1, texcoord).rgb * 2.0 - 1.0;
    float normalLen = length(normal);
    
    // Guard against far-plane / invalid depth
    bool isSky = depth >= 0.99999;
    bool isNear = depth <= 0.01;

    // --- STAGE 4: EDGE DETECTION (OUTLINES) ---
    vec2 texelSize = 1.0 / vec2(viewWidth, viewHeight);
    float edgeDepth = 0.0;
    float edgeNormal = 0.0;
    float thickness = max(outlineThickness, 0.0);

    // MANDATORY 3x3 Sampling Grid (Performance Optimized)
    for (int x = -1; x <= 1; x++) {
        for (int y = -1; y <= 1; y++) {
            if (x == 0 && y == 0) continue;
            
            vec2 offset = vec2(x, y) * texelSize * thickness;
            float neighborDepth = texture(depthtex0, texcoord + offset).r;
            vec3 neighborNormal = texture(colortex1, texcoord + offset).rgb * 2.0 - 1.0;
            float neighborNormalLen = length(neighborNormal);

            // A. Depth-based edges
            if (neighborDepth >= 0.99999) continue;
            float depthDiff = max(abs(depth - neighborDepth) - depthThreshold, 0.0);
            if (depthDiff > 0.0) {
                edgeDepth = 1.0;
            }

            // B. Normal-based edges
            if (normalLen > 0.1 && neighborNormalLen > 0.1) {
                float normalDiff = distance(normal, neighborNormal);
                if (normalDiff > normalThreshold) {
                    edgeNormal = 1.0;
                }
            }
        }
    }

    // C. Combine
    float edge = max(edgeDepth, edgeNormal);
    if (isSky || isNear || normalLen <= 0.1) edge = 0.0;
    
    // Distance Fade (Stage 5 Optional)
    edge *= clamp(1.0 - depth * 1.1, 0.0, 1.0);

    // --- STAGE 2: COLOR PROCESSING ---
    vec3 processedColor = baseColor;
    if (!isSky) {
        processedColor = applySaturation(processedColor, saturationFactor);
        processedColor = applyGamma(processedColor, gamma);
        processedColor = quantize(processedColor, celLevels);
    }

    // Debug views to isolate issues quickly
    if (debugMode == 1) {
        color = vec4(vec3(edge), 1.0);
        return;
    } else if (debugMode == 2) {
        color = vec4(baseColor, 1.0);
        return;
    } else if (debugMode == 3) {
        color = vec4(vec3(depth), 1.0);
        return;
    }

    // D. Apply outline
    if (edge > 0.5) {
        processedColor = outlineColor;
    }

    color = vec4(processedColor, 1.0);
}
