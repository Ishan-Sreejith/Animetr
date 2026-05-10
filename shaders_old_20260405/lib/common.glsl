// --- CONSTANTS & UNIFORMS ---
uniform float celLevels = 4.0;
uniform float saturationFactor = 1.2;
uniform float gamma = 0.8;
uniform float shadowThreshold = 0.1;
uniform float depthThreshold;
uniform float normalThreshold;
uniform vec3 outlineColor = vec3(0.0); // Default to black
uniform vec3 shadowTint = vec3(0.8, 0.8, 1.1); // Slightly blue shadows
uniform float lightIntensity = 1.0;
const float MIN_LIGHT = 0.15; // Prevents full-black from lightmap edge cases

uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;

// Helper to get active light source (sun vs moon)
vec3 getLightDirection() {
    // Basic day/night toggle based on worldTime
    // (Sun is active 0-12000, Moon 12000-24000)
    bool isNight = (worldTime > 12000 && worldTime < 24000);
    return normalize(isNight ? moonPosition : sunPosition);
}

// --- STEP 1: QUANTIZATION (CEL SHADING CORE) ---
float quantize(float value, float levels) {
    if (levels <= 0.0) return value;

    // Hard quantization for crisp banding (matches NPR spec)
    return floor(value * levels) / levels;
}

vec3 quantize(vec3 color, float levels) {
    if (levels <= 0.0) return color;
    return vec3(quantize(color.r, levels), quantize(color.g, levels), quantize(color.b, levels));
}

// --- STEP 2: COLOR PROCESSING ---
float getLuminance(vec3 color) {
    return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 applySaturation(vec3 color, float factor) {
    float luma = getLuminance(color);
    return mix(vec3(luma), color, factor);
}

vec3 applyGamma(vec3 color, float g) {
    return pow(max(color, vec3(0.0)), vec3(g));
}

vec3 clampLightmap(vec3 lm) {
    return max(lm, vec3(MIN_LIGHT));
}

// --- STEP 3: SHADOW MODEL ---
float getShadow(vec4 shadowPos, sampler2D shadowMap) {
    // Invalid shadow position (can happen for some passes) -> treat as fully lit
    if (shadowPos.w <= 0.00001) {
        return 1.0;
    }

    // 1. Perspective Divide (Safe even for orthogonal)
    vec3 projCoords = shadowPos.xyz / shadowPos.w;
    
    // 2. Transform to [0, 1] range for texture sampling
    projCoords = projCoords * 0.5 + 0.5;
    
    // Avoid sampling off-texture or invalid depth
    if (projCoords.x < 0.0 || projCoords.x > 1.0 ||
        projCoords.y < 0.0 || projCoords.y > 1.0 ||
        projCoords.z <= 0.0 || projCoords.z > 1.0) {
        return 1.0;
    }

    // 3. Sample the shadow map
    float closestDepth = texture(shadowMap, projCoords.xy).r;
    float currentDepth = projCoords.z;
    
    // 4. Manual robust bias for orthogonal shadows
    // This value is tuned for shadowDistance=128.0
    float bias = 0.0025; 
    return (currentDepth > closestDepth + bias) ? 0.0 : 1.0;
}

// --- STEP 6: ADVANCED EFFECTS ---
float calculateRim(vec3 N, vec3 V, float start, float end) {
    float rim = 1.0 - max(dot(N, V), 0.0);
    return smoothstep(start, end, rim);
}

vec3 calculateHardSpecular(vec3 N, vec3 L, vec3 V, float shininess, float threshold) {
    vec3 H = normalize(L + V);
    float spec = pow(max(dot(N, H), 0.0), shininess);
    return (spec > threshold) ? vec3(1.0) : vec3(0.0);
}

vec3 applyCelLighting(vec3 albedo, vec3 N, vec3 L, vec3 V, float shadowFactor) {
    float diffuse = max(dot(N, L), 0.0);
    float qDiffuse = quantize(diffuse, celLevels);
    
    // Hard shadow step (binary) using the exposed threshold
    float shadowStep = step(shadowThreshold, shadowFactor);
    float totalLight = qDiffuse * shadowStep;
    
    // Hard Specular Highlight
    vec3 specular = calculateHardSpecular(N, L, V, 32.0, 0.8) * shadowFactor;
    
    // Ambient / Shadow tinting (Prevents pitch black)
    vec3 lighting = mix(shadowTint * 0.45, vec3(1.0), totalLight + 0.2);
    
    return (albedo * lighting + specular * 0.4) * lightIntensity;
}
