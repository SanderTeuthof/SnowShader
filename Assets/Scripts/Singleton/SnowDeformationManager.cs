using UnityEngine;
using System.Collections.Generic;

public class SnowDeformationManager : MonoBehaviour
{
    private static SnowDeformationManager _instance;
    public static SnowDeformationManager Instance
    {
        get
        {
            if (_instance == null)
            {
                var go = new GameObject("SnowDeformationManager");
                _instance = go.AddComponent<SnowDeformationManager>();
                DontDestroyOnLoad(go);
            }
            return _instance;
        }
    }

    private struct DeformationCommand
    {
        public Vector3 worldPosition;
        public float strength;
        public float radius;
        public float rimWidth;
        public float rimStrength;
    }

    private List<DeformationCommand> _pendingDeformations = new List<DeformationCommand>();
    private ComputeShader _deformationShader;
    private Material _snowMaterial;
    private RenderTexture _deformationTexture;
    private Matrix4x4 _worldToUV;
    private Matrix4x4 _uvToWorld;
    private float _standardValue;
    private bool _isInitialized;

    private void Awake()
    {
        if (_instance != null && _instance != this)
        {
            Destroy(gameObject);
            return;
        }
        _instance = this;
        DontDestroyOnLoad(gameObject);
    }

    public void Initialize(Material snowMaterial, ComputeShader computeShader, Mesh snowMesh, Transform snowTransform)
    {
        _snowMaterial = snowMaterial;
        _deformationShader = computeShader;
        _deformationTexture = _snowMaterial.GetTexture("_DeformationTexture") as RenderTexture;
        _standardValue = _snowMaterial.GetFloat("_TextureStandardValue");

        // Calculate transformation matrices
        var bounds = snowMesh.bounds;
        var worldMin = snowTransform.TransformPoint(bounds.min);
        var worldMax = snowTransform.TransformPoint(bounds.max);

        _worldToUV = Matrix4x4.identity;
        _worldToUV.m00 = -1f / (worldMax.x - worldMin.x);
        _worldToUV.m11 = -1f / (worldMax.z - worldMin.z);
        _worldToUV.m03 = 1 - (worldMin.x * _worldToUV.m00);
        _worldToUV.m13 = 1 - (worldMin.z * _worldToUV.m11);

        _uvToWorld = Matrix4x4.identity;
        _uvToWorld.m00 = -(worldMax.x - worldMin.x);
        _uvToWorld.m11 = -(worldMax.z - worldMin.z);
        _uvToWorld.m03 = worldMax.x;
        _uvToWorld.m13 = worldMax.z;

        _isInitialized = true;
    }

    public void AddDeformation(Vector3 worldPos, float strength, float radius, float rimWidth, float rimStrength)
    {
        if (!_isInitialized) return;

        _pendingDeformations.Add(new DeformationCommand
        {
            worldPosition = worldPos,
            strength = strength,
            radius = radius,
            rimWidth = rimWidth,
            rimStrength = rimStrength
        });
    }

    private Vector2 WorldToUV(Vector3 worldPos)
    {
        Vector4 pos = new Vector4(worldPos.x, worldPos.z, 0, 1);
        Vector4 uv = _worldToUV * pos;
        return new Vector2(uv.x, uv.y);
    }

    private void FixedUpdate()
    {
        if (!_isInitialized || _pendingDeformations.Count == 0) return;

        var tempRT = RenderTexture.GetTemporary(
            _deformationTexture.width,
            _deformationTexture.height,
            0,
            _deformationTexture.format
        );
        tempRT.enableRandomWrite = true;
        tempRT.Create();

        Graphics.Blit(_deformationTexture, tempRT);

        int kernel = _deformationShader.FindKernel("CSMain");
        _deformationShader.SetTexture(kernel, "Result", tempRT);
        _deformationShader.SetMatrix("WorldToUV", _worldToUV);
        _deformationShader.SetMatrix("UVToWorld", _uvToWorld);
        _deformationShader.SetFloat("StandardValue", _standardValue);

        foreach (var cmd in _pendingDeformations)
        {
            Vector2 uv = WorldToUV(cmd.worldPosition);
            _deformationShader.SetVector("DeformationCenter", new Vector4(uv.x, uv.y, 0, 0));
            _deformationShader.SetFloat("DeformationRadius", cmd.radius);
            _deformationShader.SetFloat("DeformationStrength", cmd.strength);
            _deformationShader.SetFloat("RimWidth", cmd.rimWidth);
            _deformationShader.SetFloat("RimStrength", cmd.rimStrength);

            int threadGroupsX = Mathf.CeilToInt(tempRT.width / 8.0f);
            int threadGroupsY = Mathf.CeilToInt(tempRT.height / 8.0f);
            _deformationShader.Dispatch(kernel, threadGroupsX, threadGroupsY, 1);
        }

        Graphics.Blit(tempRT, _deformationTexture);
        RenderTexture.ReleaseTemporary(tempRT);
        _pendingDeformations.Clear();
    }
}