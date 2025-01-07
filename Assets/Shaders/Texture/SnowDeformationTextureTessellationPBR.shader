Shader "Custom/SnowDeformationPBR"
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
        _TextureStandardValue("Texture Standard Value", Float) = 0.8
        _DeformationTexture ("Deformation Texture", 2D) = "white" {}
        _DeformationStrength ("Deformation Strength", Float) = 1.0
        _MinTessDistance("Min Tessellation Distance", Float) = 1
        _MaxTessDistance("Max Tessellation Distance", Float) = 20
        _TessellationFactor("Tessellation Factor", Range(1, 128)) = 8
        _DeformTessellationBias("Deformation Tessellation Bias", Range(0, 10)) = 1
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

            // Textures and samplers
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);
            TEXTURE2D(_DeformationTexture); SAMPLER(sampler_DeformationTexture);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);

            // Material properties
            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float4 _Color;
                float _Glossiness;
                float _Metallic;
                float _BumpScale;
                float _SnowHeight;
                float _TextureStandardValue;
                float _DeformationStrength;
                float _MinTessDistance;
                float _MaxTessDistance;
                float _TessellationFactor;
                float _DeformTessellationBias;
                float _OcclusionStrength;
                float4 _SpecularColor;
                float4 _FresnelColor;
                float _FresnelStrength;
            CBUFFER_END

            float SampleDeformationMaxDeviation(float2 uvStart, float2 uvEnd, int samples)
            {
                float maxDeviation = 0;
                for (int i = 0; i <= samples; i++)
                {
                    float t = i / (float)samples;
                    float2 uv = lerp(uvStart, uvEnd, t);
                    float deformation = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, uv, 0).r;
                    float deviation = abs(deformation - _TextureStandardValue) / _TextureStandardValue;
                    maxDeviation = max(maxDeviation, deviation);
                }
                return maxDeviation;
            }

            float CalculateTessellationFactor(float3 p0, float2 uvStart, float2 uvEnd)
            {
                float3 camPos = _WorldSpaceCameraPos;
                float distance = length(TransformObjectToWorld(p0) - camPos);
                float distanceFactor = 1 - saturate((distance - _MinTessDistance) / (_MaxTessDistance - _MinTessDistance));
    
                // Sample multiple points along the edge
                float maxDeviation = SampleDeformationMaxDeviation(uvStart, uvEnd, 4);
    
                // Calculate base tessellation factor
                float deformFactor = lerp(0.1, 1.0, saturate(maxDeviation * _DeformTessellationBias));
    
                // Add extra tessellation for edges
                float edgeFactor = 1.0;
                if (maxDeviation > 0.01)
                {
                    // Sample perpendicular to the edge
                    float2 edgeDir = normalize(uvEnd - uvStart);
                    float2 perpDir = float2(-edgeDir.y, edgeDir.x);
                    float2 texelSize = float2(1.0/512.0, 1.0/512.0);
        
                    float maxEdgeContrast = 0;
                    for (int i = 0; i <= 4; i++)
                    {
                        float t = i / 4.0;
                        float2 centerUV = lerp(uvStart, uvEnd, t);
            
                        float d1 = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, 
                            centerUV + perpDir * texelSize.x, 0).r;
                        float d2 = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, 
                            centerUV - perpDir * texelSize.x, 0).r;
                
                        float contrast = abs(d1 - d2);
                        maxEdgeContrast = max(maxEdgeContrast, contrast);
                    }
        
                    edgeFactor = lerp(1.0, 2.0, saturate(maxEdgeContrast * 5.0));
                }
    
                return _TessellationFactor * distanceFactor * deformFactor * edgeFactor;
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
    
                // Calculate tessellation factors by checking the entire edges
                f.edge[0] = CalculateTessellationFactor(
                    patch[0].positionOS.xyz,
                    patch[0].uv,
                    patch[1].uv
                );
                f.edge[1] = CalculateTessellationFactor(
                    patch[1].positionOS.xyz,
                    patch[1].uv,
                    patch[2].uv
                );
                f.edge[2] = CalculateTessellationFactor(
                    patch[2].positionOS.xyz,
                    patch[2].uv,
                    patch[0].uv
                );
    
                // For inside tessellation, use maximum of edge factors
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
                Attributes vertex;
    
                // Standard interpolation
                vertex.positionOS = 
                    patch[0].positionOS * barycentricCoordinates.x +
                    patch[1].positionOS * barycentricCoordinates.y +
                    patch[2].positionOS * barycentricCoordinates.z;

                vertex.normalOS = normalize(
                    patch[0].normalOS * barycentricCoordinates.x +
                    patch[1].normalOS * barycentricCoordinates.y +
                    patch[2].normalOS * barycentricCoordinates.z);

                vertex.tangentOS = 
                    patch[0].tangentOS * barycentricCoordinates.x +
                    patch[1].tangentOS * barycentricCoordinates.y +
                    patch[2].tangentOS * barycentricCoordinates.z;

                vertex.uv = 
                    patch[0].uv * barycentricCoordinates.x +
                    patch[1].uv * barycentricCoordinates.y +
                    patch[2].uv * barycentricCoordinates.z;

                // Sample deformation height
                float h0 = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, vertex.uv, 0).r;
    
                // Simple height calculation: actual/standard * snowHeight
                float heightOffset = (h0 / _TextureStandardValue) * _SnowHeight;
                vertex.positionOS.xyz += vertex.normalOS * heightOffset;

                // Sample neighboring points for normal calculation
                float2 texelSize = float2(1.0 / 512.0, 1.0 / 512.0);
                float hL = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, vertex.uv - float2(texelSize.x, 0), 0).r;
                float hR = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, vertex.uv + float2(texelSize.x, 0), 0).r;
                float hD = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, vertex.uv - float2(0, texelSize.y), 0).r;
                float hU = SAMPLE_TEXTURE2D_LOD(_DeformationTexture, sampler_DeformationTexture, vertex.uv + float2(0, texelSize.y), 0).r;

                // Calculate neighbor heights using same formula
                float heightL = (hL / _TextureStandardValue) * _SnowHeight;
                float heightR = (hR / _TextureStandardValue) * _SnowHeight;
                float heightD = (hD / _TextureStandardValue) * _SnowHeight;
                float heightU = (hU / _TextureStandardValue) * _SnowHeight;

                // Calculate surface derivatives using the actual heights
                float3 tangent = normalize(float3(2.0 * texelSize.x, heightR - heightL, 0));
                float3 bitangent = normalize(float3(0, heightU - heightD, 2.0 * texelSize.y));
                float3 modifiedNormal = normalize(-cross(tangent, bitangent));
    
                // Calculate deformation intensity for normal blending
                float deformationIntensity = saturate(abs(h0 / _TextureStandardValue - 1.0) * _DeformationStrength);
    
                // Only modify normal where there's significant deformation
                if(deformationIntensity > 0.01) {
                    vertex.normalOS = normalize(lerp(vertex.normalOS, modifiedNormal, deformationIntensity));
                }

                // Transform to world space
                Varyings output;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(vertex.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(vertex.normalOS, vertex.tangentOS);

                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = float4(normalInputs.tangentWS, vertex.tangentOS.w);
                output.uv = TRANSFORM_TEX(vertex.uv, _MainTex);

                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    output.shadowCoord = TransformWorldToShadowCoord(output.positionWS);
                #endif

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                #if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                    float4 shadowCoord = input.shadowCoord;
                #elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                    float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                #else
                    float4 shadowCoord = float4(0, 0, 0, 0);
                #endif

                // Sample all textures
                half4 albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, input.uv) * _Color;
                half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, input.uv), _BumpScale);
                half occlusion = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, input.uv).r;
                float deformationValue = SAMPLE_TEXTURE2D(_DeformationTexture, sampler_DeformationTexture, input.uv).r;

                // Transform normal from tangent to world space
                float3 normalWS = normalize(input.normalWS);
                float3 tangentWS = normalize(input.tangentWS.xyz);
                float3 bitangentWS = normalize(cross(normalWS, tangentWS) * input.tangentWS.w);
                float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
                normalWS = normalize(mul(normalTS, tangentToWorld));

                // Get view direction in world space
                float3 viewDirWS = normalize(_WorldSpaceCameraPos - input.positionWS);

                // Get main light
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
                        Light light = GetAdditionalLight(lightIndex, input.positionWS);
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

                // Optional debug views
                // return half4(normalWS * 0.5 + 0.5, 1);               // Normal map visualization
                // return half4(occlusion.xxx, 1);                      // AO visualization
                // return half4(directSpecular, 1);                     // Specular visualization
                // return half4(ambient, 1);                            // Ambient visualization
                // return half4(deformationValue.xxx, 1);              // Deformation visualization
                // return half4(NdotL.xxx, 1);                         // Direct lighting visualization
    
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