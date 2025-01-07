using UnityEngine;

public class SnowDeformer : MonoBehaviour
{
    [Header("Deformation Settings")]
    [SerializeField] private float _deformationStrength = 1f;
    [SerializeField] private float _radiusMultiplier = 1f;
    [SerializeField] private LayerMask _snowLayer;

    [Header("Rim Settings")]
    [SerializeField] private float _rimWidth = 0.1f;
    [SerializeField] private float _rimStrength = 0.5f;

    [Header("Optional")]
    [SerializeField] private bool _deformOnCollision = true;
    [SerializeField] private bool _deformAtPosition = false;

    private SphereCollider _sphereCollider;
    private float _scaledRadius;
    private bool _initialized;

    private void Start()
    {
        _sphereCollider = GetComponent<SphereCollider>();
        if (_sphereCollider == null)
        {
            Debug.LogError("SnowDeformer requires a SphereCollider component!");
            enabled = false;
            return;
        }

        UpdateScaledRadius();

        // Find snow
        var snowRenderer = Physics.Raycast(
            transform.position,
            Vector3.down,
            out RaycastHit hit,
            10f,
            _snowLayer
        );

        if (snowRenderer)
        {
            var meshRenderer = hit.collider.GetComponent<MeshRenderer>();
            var snowMesh = hit.collider.GetComponent<MeshFilter>().mesh;

            // Initialize manager if needed
            if (!_initialized)
            {
                var computeShader = Resources.Load<ComputeShader>("SnowDeformation");
                SnowDeformationManager.Instance.Initialize(
                    meshRenderer.material,
                    computeShader,
                    snowMesh,
                    hit.collider.transform
                );
                _initialized = true;
            }
        }
    }

    private void UpdateScaledRadius()
    {
        float maxScale = Mathf.Max(transform.lossyScale.x, Mathf.Max(transform.lossyScale.y, transform.lossyScale.z));
        _scaledRadius = _sphereCollider.radius * maxScale * _radiusMultiplier;
    }

    private void Update()
    {
        if (!_deformAtPosition || !_initialized) return;
        DeformSnowAtWorldPosition(transform.position, _deformationStrength);
    }

    private void OnCollisionStay(Collision collision)
    {
        if (!_deformOnCollision || !_initialized) return;

        foreach (var contact in collision.contacts)
        {
            DeformSnowAtWorldPosition(contact.point, _deformationStrength);
        }
    }

    public void DeformSnowAtWorldPosition(Vector3 worldPos, float strength)
    {
        if (!_initialized) return;

        Ray ray = new Ray(worldPos + Vector3.up * 10f, Vector3.down);
        if (Physics.Raycast(ray, out RaycastHit hit, 20f, _snowLayer))
        {
            SnowDeformationManager.Instance.AddDeformation(
                hit.point,
                strength,
                _scaledRadius,
                _rimWidth,
                _rimStrength
            );
        }
    }
}