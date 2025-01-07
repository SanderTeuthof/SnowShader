Shader "Unlit/SnowDeformationTextureTessellation"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _SnowHeight ("Snow Height", Float) = 0.5
        _TextureStandardValue("Texture Standard Value", Float) = 0.8
        _DeformationTexture ("Deformation Texture", 2D) = "white" {}
        _DeformationStrength ("Deformation Strength", Float) = 1.0
        _MinTessDistance("Min Tessellation Distance", Float) = 1
        _MaxTessDistance("Max Tessellation Distance", Float) = 20
        _TessellationFactor("Tessellation Factor", Range(1, 64)) = 8
        _DeformTessellationBias("Deformation Tessellation Bias", Range(0, 10)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma hull Hull
            #pragma domain Domain
            #pragma fragment Frag
            #pragma target 4.6

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            float4 _BaseColor;
            float _SnowHeight;
            float _TextureStandardValue;
            float _DeformationStrength;
            sampler2D _DeformationTexture;
            float4 _DeformationTexture_ST;
            float _MinTessDistance;
            float _MaxTessDistance;
            float _TessellationFactor;
            float _DeformTessellationBias;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct TessellationControlPoint
            {
                float4 positionOS : INTERNALTESSPOS;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };

            TessellationControlPoint Vert(Attributes input)
            {
                TessellationControlPoint output;
                output.positionOS = input.positionOS;
                output.uv = input.uv;
                output.normalOS = input.normalOS;
                return output;
            }

            float CalculateTessellationFactor(float3 p0, float deformation)
            {
                float3 camPos = _WorldSpaceCameraPos;
                float distance = length(TransformObjectToWorld(p0) - camPos);
                
                float distanceFactor = 1 - saturate((distance - _MinTessDistance) / (_MaxTessDistance - _MinTessDistance));
                
                float deviation = abs(deformation - _TextureStandardValue);
                float normalizedDeviation = deviation / _TextureStandardValue;
                
                float deformFactor = lerp(0.1, 1.0, saturate(normalizedDeviation * _DeformTessellationBias));
                
                return _TessellationFactor * distanceFactor * deformFactor;
            }

            TessellationFactors PatchConstantFunction(
                InputPatch<TessellationControlPoint, 3> patch,
                uint patchID : SV_PrimitiveID)
            {
                TessellationFactors f;

                float def0 = tex2Dlod(_DeformationTexture, float4(patch[0].uv, 0, 0)).r;
                float def1 = tex2Dlod(_DeformationTexture, float4(patch[1].uv, 0, 0)).r;
                float def2 = tex2Dlod(_DeformationTexture, float4(patch[2].uv, 0, 0)).r;

                f.edge[0] = CalculateTessellationFactor(patch[0].positionOS, (def1 + def2) * 0.5);
                f.edge[1] = CalculateTessellationFactor(patch[1].positionOS, (def2 + def0) * 0.5);
                f.edge[2] = CalculateTessellationFactor(patch[2].positionOS, (def0 + def1) * 0.5);
                
                f.inside = (f.edge[0] + f.edge[1] + f.edge[2]) / 3.0;

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
            VertexOutput Domain(
                TessellationFactors factors,
                OutputPatch<TessellationControlPoint, 3> patch,
                float3 barycentricCoordinates : SV_DomainLocation)
            {
                Attributes vertex;

                vertex.positionOS = 
                    patch[0].positionOS * barycentricCoordinates.x +
                    patch[1].positionOS * barycentricCoordinates.y +
                    patch[2].positionOS * barycentricCoordinates.z;

                vertex.normalOS = 
                    patch[0].normalOS * barycentricCoordinates.x +
                    patch[1].normalOS * barycentricCoordinates.y +
                    patch[2].normalOS * barycentricCoordinates.z;

                vertex.uv = 
                    patch[0].uv * barycentricCoordinates.x +
                    patch[1].uv * barycentricCoordinates.y +
                    patch[2].uv * barycentricCoordinates.z;

                float deformationValue = tex2Dlod(_DeformationTexture, float4(vertex.uv, 0, 0)).r;
                float heightOffset = lerp(0.0, _SnowHeight, deformationValue / _TextureStandardValue);
                
                vertex.positionOS.xyz += vertex.normalOS * heightOffset * _DeformationStrength;

                VertexOutput output;
                output.positionCS = TransformObjectToHClip(vertex.positionOS);
                output.uv = vertex.uv;
                output.normalWS = TransformObjectToWorldNormal(vertex.normalOS);
                output.positionWS = TransformObjectToWorld(vertex.positionOS);
                
                return output;
            }

            half4 Frag(VertexOutput input) : SV_Target
            {
                half4 color = _BaseColor;
                float deformationValue = tex2D(_DeformationTexture, input.uv).r;
                color.rgb *= 1.0 - (deformationValue * _DeformationStrength);
                return deformationValue;
            }
            ENDHLSL
        }
    }
}