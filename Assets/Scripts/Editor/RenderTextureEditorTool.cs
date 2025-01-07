using UnityEngine;
using UnityEditor;

public class RenderTextureEditorTool : EditorWindow
{
    private RenderTexture renderTexture;
    private float fillValue = 0.8f;
    private FillMode selectedFillMode = FillMode.Flat;
    private Gradient gradient = new Gradient();
    private AnimationCurve curve;
    private bool showDebugInfo = false;

    public enum FillMode
    {
        Flat,
        Gradient,
        Graph
    }

    [MenuItem("Tools/Render Texture Filler")]
    public static void ShowWindow()
    {
        GetWindow<RenderTextureEditorTool>("Render Texture Filler");
    }

    private void OnEnable()
    {
        // Initialize gradient with grayscale values
        gradient = new Gradient();
        var colorKeys = new GradientColorKey[]
        {
            new GradientColorKey(Color.black, 0.0f),
            new GradientColorKey(Color.white, 1.0f)
        };
        var alphaKeys = new GradientAlphaKey[]
        {
            new GradientAlphaKey(1.0f, 0.0f),
            new GradientAlphaKey(1.0f, 1.0f)
        };
        gradient.SetKeys(colorKeys, alphaKeys);

        // Initialize default curve
        if (curve == null)
        {
            curve = new AnimationCurve();
            curve.AddKey(new Keyframe(0, 0, 0, 1));  // Start point with linear slope
            curve.AddKey(new Keyframe(1, 1, 1, 0));  // End point with linear slope
        }
    }

    private void OnGUI()
    {

        GUILayout.Label("Render Texture Filler", EditorStyles.boldLabel);

        renderTexture = (RenderTexture)EditorGUILayout.ObjectField("Render Texture", renderTexture, typeof(RenderTexture), false);

        if (renderTexture != null)
        {
            EditorGUILayout.LabelField($"Current Format: {renderTexture.format}");
            EditorGUILayout.LabelField($"Random Write: {renderTexture.enableRandomWrite}");

            bool needsNewTexture = !renderTexture.enableRandomWrite ||
                                 renderTexture.format != RenderTextureFormat.ARGBFloat;

            if (needsNewTexture)
            {
                EditorGUILayout.HelpBox(
                    "Current RenderTexture needs random write access and ARGBFloat format.",
                    MessageType.Warning
                );

                if (GUILayout.Button("Create New RT with Correct Settings"))
                {
                    CreateNewRenderTexture();
                }
            }
        }

        selectedFillMode = (FillMode)EditorGUILayout.EnumPopup("Fill Mode", selectedFillMode);

        switch (selectedFillMode)
        {
            case FillMode.Flat:
                DrawFlatControls();
                break;
            case FillMode.Gradient:
                DrawGradientControls();
                break;
            case FillMode.Graph:
                DrawGraphControls();
                break;
        }

        if (GUILayout.Button("Fill Render Texture"))
        {
            if (renderTexture == null)
            {
                Debug.LogError("No Render Texture selected!");
                return;
            }

            var tempRT = CreateTemporaryRenderTexture(renderTexture.width, renderTexture.height);
            FillRenderTexture(tempRT, selectedFillMode);

            Graphics.Blit(tempRT, renderTexture);
            RenderTexture.ReleaseTemporary(tempRT);

            Debug.Log($"Render Texture filled with mode: {selectedFillMode}");
        }
    }

    private void DrawFlatControls()
    {
        fillValue = EditorGUILayout.Slider("Fill Value", fillValue, 0.0f, 1.0f);

        showDebugInfo = EditorGUILayout.Foldout(showDebugInfo, "Debug Info");
        if (showDebugInfo)
        {
            EditorGUI.indentLevel++;
            EditorGUILayout.LabelField($"Raw Value: {fillValue:F4}");
            EditorGUI.indentLevel--;
        }
    }

    private void DrawGradientControls()
    {
        gradient = EditorGUILayout.GradientField("Fill Gradient", gradient);
    }

    private void DrawGraphControls()
    {
        EditorGUILayout.LabelField("Curve Editor", EditorStyles.boldLabel);
        curve = EditorGUILayout.CurveField("Value Curve", curve, Color.white, new Rect(0, 0, 1, 1));
    }

    private RenderTexture CreateTemporaryRenderTexture(int width, int height)
    {
        var desc = new RenderTextureDescriptor(width, height, RenderTextureFormat.ARGBFloat, 0)
        {
            enableRandomWrite = true,
            sRGB = false,
            useMipMap = false
        };

        var rt = RenderTexture.GetTemporary(desc);
        rt.Create();

        return rt;
    }

    private void CreateNewRenderTexture()
    {
        if (renderTexture == null) return;

        var desc = new RenderTextureDescriptor(
            renderTexture.width,
            renderTexture.height,
            RenderTextureFormat.ARGBFloat,
            0
        )
        {
            enableRandomWrite = true,
            sRGB = false,
            useMipMap = false
        };

        var newRT = new RenderTexture(desc);
        newRT.Create();

        Graphics.Blit(renderTexture, newRT);
        renderTexture = newRT;
    }

    private void FillRenderTexture(RenderTexture target, FillMode fillMode)
    {
        ComputeShader computeShader = AssetDatabase.LoadAssetAtPath<ComputeShader>(
            "Assets/Scripts/Editor/CopyBufferToTexture.compute"
        );

        if (computeShader == null)
        {
            Debug.LogError("Could not find CopyBufferToTexture.compute shader. Make sure it exists in the Assets folder.");
            return;
        }

        int totalPixels = target.width * target.height;
        ComputeBuffer buffer = new ComputeBuffer(totalPixels * 4, sizeof(float));

        try
        {
            float[] data = new float[totalPixels * 4];

            switch (fillMode)
            {
                case FillMode.Flat:
                    for (int i = 0; i < data.Length; i++)
                    {
                        data[i] = fillValue;
                    }
                    break;

                case FillMode.Gradient:
                    for (int y = 0; y < target.height; y++)
                    {
                        for (int x = 0; x < target.width; x++)
                        {
                            int pixelIndex = (y * target.width + x) * 4;
                            float normalizedX = (float)x / target.width;
                            Color gradientColor = gradient.Evaluate(normalizedX);
                            float value = (gradientColor.r + gradientColor.g + gradientColor.b) / 3.0f;
                            data[pixelIndex] = value;
                            data[pixelIndex + 1] = value;
                            data[pixelIndex + 2] = value;
                            data[pixelIndex + 3] = value;
                        }
                    }
                    break;

                case FillMode.Graph:
                    for (int y = 0; y < target.height; y++)
                    {
                        for (int x = 0; x < target.width; x++)
                        {
                            int pixelIndex = (y * target.width + x) * 4;
                            float normalizedX = (float)x / target.width;
                            float value = curve.Evaluate(normalizedX);
                            data[pixelIndex] = value;
                            data[pixelIndex + 1] = value;
                            data[pixelIndex + 2] = value;
                            data[pixelIndex + 3] = value;
                        }
                    }
                    break;
            }

            buffer.SetData(data);

            int kernel = computeShader.FindKernel("CSMain");
            computeShader.SetBuffer(kernel, "InputBuffer", buffer);
            computeShader.SetTexture(kernel, "Result", target);
            computeShader.SetInt("TextureWidth", target.width);
            computeShader.SetInt("TextureHeight", target.height);

            int threadGroupsX = Mathf.CeilToInt(target.width / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(target.height / 8.0f);
            computeShader.Dispatch(kernel, threadGroupsX, threadGroupsY, 1);
        }
        finally
        {
            buffer.Release();
        }
    }
}