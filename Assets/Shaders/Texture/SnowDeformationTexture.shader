Shader "Unlit/SnowDeformationTexture"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _SnowHeight ("Snow Height", Float) = 0.5
        _TextureStandardValue("Texture Standard Value", Float) = 0.8
        _DeformationTexture ("Deformation Texture", 2D) = "white" {}
        _DeformationStrength ("Deformation Strength", Float) = 1.0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        Pass
        {
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #pragma target 4.6
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // Declare properties
            float4 _BaseColor;
            float _SnowHeight;
            float _TextureStandardValue;
            float _DeformationStrength;
            sampler2D _DeformationTexture;
            float4 _DeformationTexture_ST;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv : TEXCOORD0;
                float3 normalOS : NORMAL;
            };

            struct VertexOutput
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
            };

            // Helper function to determine which channel to sample based on UV coordinates
            float GetQuadrantDeformation(float4 texColor, float2 uv)
            {
                // Determine which quadrant we're in
                bool isLeft = uv.x < 0.5;
                bool isTop = uv.y >= 0.5;
                
                if (isTop && isLeft)
                    return texColor.r;  // Top-left: red channel
                else if (isTop && !isLeft)
                    return texColor.g;  // Top-right: green channel
                else if (!isTop && isLeft)
                    return texColor.b;  // Bottom-left: blue channel
                else
                    return texColor.a;  // Bottom-right: alpha channel
            }

            // Vertex Shader
            VertexOutput Vert(Attributes input)
            {
                VertexOutput output;
                
                // Base vertex position in object space
                float3 basePosition = input.positionOS.xyz;
                
                // Sample all channels of deformation texture
                float4 deformationColor = tex2Dlod(_DeformationTexture, float4(input.uv, 0, 0));
                
                // Get appropriate channel based on UV position
                float deformationValue = GetQuadrantDeformation(deformationColor, input.uv);
                
                // Calculate height offset
                float heightOffset = lerp(0.0, _SnowHeight, deformationValue / _TextureStandardValue);
                
                // Apply deformation to vertex position
                basePosition += input.normalOS * heightOffset * _DeformationStrength;
                
                // Transform to clip space and output
                output.positionCS = TransformObjectToHClip(float4(basePosition, 1.0));
                output.uv = input.uv;
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                
                return output;
            }

            // Fragment Shader
            half4 Frag(VertexOutput input) : SV_Target
            {
                half4 color = _BaseColor;
                
                // Sample all channels of deformation texture
                float4 deformationColor = tex2D(_DeformationTexture, input.uv);
                
                // Get appropriate channel based on UV position
                float deformationValue = GetQuadrantDeformation(deformationColor, input.uv);
                
                // Adjust color based on deformation
                color.rgb *= 1.0 - (deformationValue * _DeformationStrength);
                
                return deformationValue;
            }
            ENDHLSL
        }
    }
    FallBack "Diffuse"
}