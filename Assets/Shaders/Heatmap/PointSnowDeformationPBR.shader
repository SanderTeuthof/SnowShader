Shader "Custom/PointSnowDeformationPBR"
{
    Properties 
    {
        // PBR properties
        _Color ("Base Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}
        _OcclusionStrength("Occlusion Strength", Range(0.0, 1.0)) = 1.0
        _SpecularColor("Specular Color", Color) = (1,1,1,1)
        _FresnelColor("Fresnel Color", Color) = (1,1,1,1)
        _FresnelStrength("Fresnel Strength", Range(0,2)) = 0.5
        
        // Snow deformation properties
        _SnowHeight ("Snow Height", Float) = 0.5
        _DeformationStrength ("Deformation Strength", Float) = 1.0
        _MinTessDistance("Min Tessellation Distance", Float) = 1
        _MaxTessDistance("Max Tessellation Distance", Float) = 20
        _TessellationFactor("Tessellation Factor", Range(1, 128)) = 8
        _MaxDeformDistance("Max Deformation Distance", Float) = 0.1
        _RimHeight("Rim Height", Range(0, 1)) = 0.2
        _RimWidth("Rim Width", Range(0, 1)) = 0.1
    }

    SubShader
    {
        Tags { 
            "RenderType"="Opaque" 
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
        }
        LOD 300

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode" = "UniversalForward" }

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.6

            #pragma vertex Vert
            #pragma hull Hull
            #pragma domain Domain
            #pragma fragment Frag

            // Lighting keywords
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"

            #define MAX_DEFORM_POINTS 20

            // Textures and samplers
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);

            StructuredBuffer<float4> _DeformPoints;
            int _NumDeformPoints;

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _Glossiness;
                float _Metallic;
                float _BumpScale;
                float _SnowHeight;
                float _DeformationStrength;
                float _MinTessDistance;
                float _MaxTessDistance;
                float _TessellationFactor;
                float _MaxDeformDistance;
                float _RimHeight;
                float _RimWidth;
                float _OcclusionStrength;
                float4 _SpecularColor;
                float4 _FresnelColor;
                float _FresnelStrength;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct TessellationControlPoint
            {
                float4 positionOS : INTERNALTESSPOS;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord : TEXCOORD4;
                #endif
            };

            void CalculatePointAndLineDeformation(in float4 deformPoint, in float3 worldPos, out float depression, out float rim, out bool isLine)
            {
                float2 pointPos = deformPoint.xy;
                float radius = deformPoint.z;
                float sequenceData = deformPoint.w;
    
                // Initialize outputs
                depression = 0;
                rim = 0;
                isLine = false;

                // Calculate point depression first
                float pointDepression = 0;
                {
                    float2 delta = float2(worldPos.x, worldPos.z) - pointPos;
                    float distSq = dot(delta, delta);
                    float radiusSq = radius * radius;
        
                    if (distSq <= radiusSq)
                    {
                        float dist = sqrt(distSq);
                        float normDist = dist / radius;
                        pointDepression = radius * (1.0 - sqrt(1.0 - (1.0 - normDist * normDist)));
                    }
                }

                // Calculate line depression if part of a sequence
                float lineDepression = 0;
                float lineRim = 0;
                if (sequenceData > 0)
                {
                    isLine = true;
                    int currentId = floor(sequenceData);
                    float sequence = (sequenceData - currentId) * 10000;
        
                    // Find next point in sequence
                    float4 nextPoint = float4(0,0,0,0);
                    bool foundNext = false;
        
                    for (int i = 0; i < _NumDeformPoints; i++)
                    {
                        float4 checkPoint = _DeformPoints[i];
                        int checkId = floor(checkPoint.w);
                        float checkSequence = (checkPoint.w - checkId) * 10000;
            
                        if (checkId == currentId && 
                            abs(checkSequence - sequence) < 2 && 
                            checkSequence > sequence)
                        {
                            nextPoint = checkPoint;
                            foundNext = true;
                            break;
                        }
                    }
        
                    if (foundNext)
                    {
                        float2 lineStart = pointPos;
                        float2 lineEnd = nextPoint.xy;
                        float2 lineDir = normalize(lineEnd - lineStart);
                        float lineLength = length(lineEnd - lineStart);
            
                        float2 toPoint = float2(worldPos.x, worldPos.z) - lineStart;
                        float projLength = dot(toPoint, lineDir);
                        float2 projPoint = lineStart + lineDir * projLength;
            
                        float2 perpVector = float2(worldPos.x, worldPos.z) - projPoint;
                        float perpDist = length(perpVector);
            
                        // Interpolate radius along line
                        float t = saturate(projLength / lineLength);
                        float interpolatedRadius = lerp(radius, nextPoint.z, t);
            
                        if (projLength >= 0 && projLength <= lineLength && perpDist <= interpolatedRadius)
                        {
                            float normDist = perpDist / interpolatedRadius;
                            lineDepression = sqrt(1 - normDist * normDist) * interpolatedRadius;
                
                            if (perpDist > interpolatedRadius * 0.8)
                            {
                                float rimDist = abs(normDist - 0.9);
                                lineRim = exp(-rimDist * rimDist * 32) * _RimHeight;
                            }
                        }
                    }
                }

                // Take the stronger depression between point and line
                depression = max(pointDepression, lineDepression);
                // Only use rim from line deformation
                rim = lineRim;
            }

            float2 CalculateDeformation(float3 worldPos)
            {
                float totalDepression = 0;
                float totalRim = 0;

                for (int i = 0; i < _NumDeformPoints; i++)
                {
                    float4 deformPoint = _DeformPoints[i];
        
                    if (deformPoint.z <= 0) // z is radius
                        continue;

                    float2 delta = float2(worldPos.x, worldPos.z) - deformPoint.xy;
                    float quickDistSq = dot(delta, delta);
                    if (quickDistSq > _MaxDeformDistance * _MaxDeformDistance)
                        continue;

                    float depression, rim;
                    bool isLine;
                    CalculatePointAndLineDeformation(deformPoint, worldPos, depression, rim, isLine);
        
                    totalDepression = min(totalDepression, -depression * _DeformationStrength);
                    if (isLine)
                    {
                        totalRim = max(totalRim, rim);
                    }
                }

                return float2(totalDepression, totalRim);
            }

            float CalculateTessellationFactor(float3 worldPos)
            {
                float3 camPos = _WorldSpaceCameraPos;
                float distance = length(worldPos - camPos);
                float distanceFactor = 1 - saturate((distance - _MinTessDistance) / (_MaxTessDistance - _MinTessDistance));
                
                float deformFactor = 0;
                for (int i = 0; i < _NumDeformPoints; i++)
                {
                    float4 deformPoint = _DeformPoints[i];
                    if (deformPoint.z <= 0) continue; // z is radius

                    float2 delta = float2(worldPos.x, worldPos.z) - deformPoint.xy;
                    float distSq = dot(delta, delta);
                    float radiusSq = (deformPoint.z + _RimWidth) * (deformPoint.z + _RimWidth);
                    
                    if (distSq < radiusSq)
                    {
                        deformFactor = 1;
                        break;
                    }
                }

                return _TessellationFactor * distanceFactor * lerp(0.25, 1.0, deformFactor);
            }

            TessellationControlPoint Vert(Attributes input)
            {
                TessellationControlPoint output;
                output.positionOS = input.positionOS;
                output.normalOS = input.normalOS;
                output.tangentOS = input.tangentOS;
                output.uv = input.uv;
                return output;
            }

            TessellationFactors PatchConstantFunction(
                InputPatch<TessellationControlPoint, 3> patch,
                uint patchID : SV_PrimitiveID)
            {
                TessellationFactors f;
    
                // Transform positions to world space before calculating tessellation factors
                float3 worldPos0 = TransformObjectToWorld(patch[0].positionOS.xyz);
                float3 worldPos1 = TransformObjectToWorld(patch[1].positionOS.xyz);
                float3 worldPos2 = TransformObjectToWorld(patch[2].positionOS.xyz);
    
                f.edge[0] = CalculateTessellationFactor(worldPos0);
                f.edge[1] = CalculateTessellationFactor(worldPos1);
                f.edge[2] = CalculateTessellationFactor(worldPos2);
    
                f.inside = max(f.edge[0], max(f.edge[1], f.edge[2]));
    
                return f;
            }

            [domain("tri")]
            [partitioning("fractional_odd")]
            [outputtopology("triangle_cw")]
            [outputcontrolpoints(3)]
            [patchconstantfunc("PatchConstantFunction")]
            TessellationControlPoint Hull(
                InputPatch<TessellationControlPoint, 3> patch,
                uint id : SV_OutputControlPointID,
                uint patchID : SV_PrimitiveID)
            {
                return patch[id];
            }

            [domain("tri")]
            Varyings Domain(
                TessellationFactors factors,
                OutputPatch<TessellationControlPoint, 3> patch,
                float3 barycentricCoordinates : SV_DomainLocation)
            {
                Attributes domainVertex;
                // Standard interpolation
                domainVertex.positionOS = 
                    patch[0].positionOS * barycentricCoordinates.x +
                    patch[1].positionOS * barycentricCoordinates.y +
                    patch[2].positionOS * barycentricCoordinates.z;
                domainVertex.normalOS = normalize(
                    patch[0].normalOS * barycentricCoordinates.x +
                    patch[1].normalOS * barycentricCoordinates.y +
                    patch[2].normalOS * barycentricCoordinates.z);
                domainVertex.tangentOS = 
                    patch[0].tangentOS * barycentricCoordinates.x +
                    patch[1].tangentOS * barycentricCoordinates.y +
                    patch[2].tangentOS * barycentricCoordinates.z;
                domainVertex.uv = 
                    patch[0].uv * barycentricCoordinates.x +
                    patch[1].uv * barycentricCoordinates.y +
                    patch[2].uv * barycentricCoordinates.z;

                // First, offset the vertex by snow height along the normal
                float3 originalPosOS = domainVertex.positionOS.xyz;
                domainVertex.positionOS.xyz += domainVertex.normalOS * _SnowHeight;

                // Transform to world space for deformation calculation
                float3 worldPos = TransformObjectToWorld(domainVertex.positionOS.xyz);
                float3 preDeformPosWS = worldPos;
    
                // Calculate deformation in world space
                float2 deform = CalculateDeformation(worldPos);
                float totalDeformation = deform.x + deform.y;
    
                // Clamp the deformation to not go below the original surface
                float maxDeformation = -_SnowHeight;
                totalDeformation = max(totalDeformation, maxDeformation);

                // Sample neighboring points for normal calculation
                float epsilon = 0.01;
                float3 posX = worldPos + float3(epsilon, 0, 0);
                float3 negX = worldPos - float3(epsilon, 0, 0);
                float3 posZ = worldPos + float3(0, 0, epsilon);
                float3 negZ = worldPos - float3(0, 0, epsilon);

                float2 deformX1 = CalculateDeformation(posX);
                float2 deformX2 = CalculateDeformation(negX);
                float2 deformZ1 = CalculateDeformation(posZ);
                float2 deformZ2 = CalculateDeformation(negZ);

                // Calculate surface derivatives using the actual deformation heights
                float3 tangent = normalize(float3(2.0 * epsilon, -(deformX1.x - deformX2.x), 0));
                float3 bitangent = normalize(float3(0, -(deformZ1.x - deformZ2.x), 2.0 * epsilon));
    
                // Calculate new normal from the deformed surface
                float3 newNormalWS = normalize(-cross(tangent, bitangent));
                float3 newNormalOS = TransformWorldToObjectNormal(newNormalWS);

                // Calculate deformation intensity for normal blending
                float deformStrength = saturate(abs(totalDeformation) / (_SnowHeight * 0.5));
                domainVertex.normalOS = normalize(lerp(domainVertex.normalOS, newNormalOS, deformStrength));

                // Apply deformation along normal
                domainVertex.positionOS.xyz += domainVertex.normalOS * totalDeformation;

                // Transform to clip space
                Varyings output;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(domainVertex.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(domainVertex.normalOS, domainVertex.tangentOS);
    
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = float4(normalInputs.tangentWS, domainVertex.tangentOS.w);
                output.uv = TRANSFORM_TEX(domainVertex.uv, _MainTex);
    
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    output.shadowCoord = TransformWorldToShadowCoord(preDeformPosWS);
                #endif
    
                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = input.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    // Calculate shadow coordinates from estimated pre-deformed position
                    float3 estimatedDeformation = input.normalWS * CalculateDeformation(input.positionWS).x * _SnowHeight;
                    float3 preDeformPosWS = input.positionWS - estimatedDeformation;
                    float4 shadowCoord = TransformWorldToShadowCoord(preDeformPosWS);
                #else
                    float4 shadowCoord = float4(0, 0, 0, 0);
                #endif

                // Sample all textures
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv) * _Color;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).r;

                // Transform normal from tangent to world space
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = normalize(cross(normalWS, tangentWS) * input.tangentWS.w);
                float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
                normalWS = normalize(mul(normalTS, tangentToWorld));

                // Get view direction in world space
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - input.positionWS);

                // Get main light with shadows
                Light mainLight = GetMainLight(shadowCoord);

                // Direct lighting
                float NdotL = saturate(dot(normalWS, mainLight.direction));
                half3 directDiffuse = mainLight.color * mainLight.shadowAttenuation * NdotL;

                // Specular
                float3 halfVector = normalize(mainLight.direction + viewDirWS);
                float NdotH = saturate(dot(normalWS, halfVector));
                float NdotV = saturate(dot(normalWS, viewDirWS));
    
                // Cook-Torrance specular calculation
                float roughness = 1 - _Glossiness;
                float roughnessSq = roughness * roughness;
                float d = NdotH * NdotH * (roughnessSq - 1) + 1;
                float specularTerm = roughnessSq / (d * d * max(0.1, NdotL * NdotV) * (4 * roughness + 2));
                half3 directSpecular = specularTerm * mainLight.color * mainLight.shadowAttenuation * _SpecularColor.rgb;

                // Ambient lighting
                half3 ambient = SampleSH(normalWS) * occlusion;
    
                // Additional lights
                #ifdef _ADDITIONAL_LIGHTS
                    uint pixelLightCount = GetAdditionalLightsCount();
                    for (uint lightIndex = 0u; lightIndex < pixelLightCount; ++lightIndex)
                    {
                        Light light = GetAdditionalLight(lightIndex, input.positionWS, shadowCoord);
                        float addNdotL = saturate(dot(normalWS, light.direction));
                        directDiffuse += light.color * light.distanceAttenuation * light.shadowAttenuation * addNdotL;
            
                        // Additional specular
                        float3 addHalfVector = normalize(light.direction + viewDirWS);
                        float addNdotH = saturate(dot(normalWS, addHalfVector));
                        float addSpecularTerm = pow(addNdotH, _Glossiness * 100.0);
                        directSpecular += addSpecularTerm * light.color * light.distanceAttenuation * light.shadowAttenuation * _SpecularColor.rgb;
                    }
                #endif

                // Final color composition
                half3 finalColor = albedo.rgb * (directDiffuse + ambient) + directSpecular;

                // Apply fresnel rim lighting
                float fresnel = pow(1.0 - NdotV, 5.0) * _FresnelStrength;
                finalColor += fresnel * _FresnelColor.rgb;

                return half4(finalColor, albedo.a);
            }

            ENDHLSL
        }

        // Shadow casting support
        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthOnly"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}