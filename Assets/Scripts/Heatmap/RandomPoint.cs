using UnityEngine;

public class RandomPoint : MonoBehaviour
{
    [SerializeField] private Material snowMaterial;
    [SerializeField] private float minRadius = 0.5f;
    [SerializeField] private float maxRadius = 1.5f;
    [SerializeField] private int maxPointsPerLine = 8; // Maximum points in a single line
    [SerializeField] private float lineSpacing = 0.2f; // Space between line points

    private ComputeBuffer deformBuffer;
    private const int MAX_DEFORM_POINTS = 16;
    private Vector4[] points;
    private float timer;
    private int currentPointIndex;
    private Bounds objectBounds;

    // Line creation variables
    private Vector2 lastPosition;
    private int currentLineId = 1;
    private int currentLinePoint = 0;
    private bool isDrawingLine = true;

    private void Start()
    {
        // Get the object's bounds for spawning points
        MeshFilter meshFilter = GetComponent<MeshFilter>();
        if (meshFilter != null)
        {
            objectBounds = meshFilter.mesh.bounds;
            // Transform bounds to world space
            Bounds worldBounds = TransformBoundsToWorldSpace(objectBounds);
            objectBounds = worldBounds;
        }

        // Initialize the buffer and point array
        points = new Vector4[MAX_DEFORM_POINTS];
        deformBuffer = new ComputeBuffer(MAX_DEFORM_POINTS, 4 * sizeof(float)); // float4

        // Set initial values
        for (int i = 0; i < MAX_DEFORM_POINTS; i++)
        {
            points[i] = new Vector4(0, 0, 0, 0);
        }

        // Set the buffer to the material
        snowMaterial.SetBuffer("_DeformPoints", deformBuffer);
        snowMaterial.SetInt("_NumDeformPoints", MAX_DEFORM_POINTS);

        // Initial upload
        deformBuffer.SetData(points);
    }

    private Bounds TransformBoundsToWorldSpace(Bounds localBounds)
    {
        var center = transform.TransformPoint(localBounds.center);
        var extents = localBounds.extents;
        var axisX = transform.TransformVector(extents.x, 0, 0);
        var axisZ = transform.TransformVector(0, 0, extents.z);

        extents.x = Mathf.Abs(axisX.x) + Mathf.Abs(axisZ.x);
        extents.z = Mathf.Abs(axisX.z) + Mathf.Abs(axisZ.z);

        return new Bounds(center, new Vector3(extents.x * 2, 0, extents.z * 2));
    }

    private void Update()
    {
        timer += Time.deltaTime;
        if (timer >= 0.5f)
        {
            timer = 0;
            if (currentLinePoint > maxPointsPerLine) // 70% chance to start a new line
            {
                StartNewLine();
            }
            else
            {
                AddLinePoint(); // Single point
            }
        }
    }

    private void StartNewLine()
    {
        isDrawingLine = true;
        currentLineId++;
        currentLinePoint = 0;
        // Start position for the line
        lastPosition = new Vector2(
            Random.Range(objectBounds.min.x, objectBounds.max.x),
            Random.Range(objectBounds.min.z, objectBounds.max.z)
        );
        AddLinePoint();
    }

    private void AddLinePoint()
    {
        if (currentLinePoint >= maxPointsPerLine)
        {
            isDrawingLine = false;
            return;
        }

        // Calculate next position in the line
        Vector2 direction = Random.insideUnitCircle.normalized;
        Vector2 newPosition = lastPosition + direction * lineSpacing;

        // Create the point with sequence data in w component
        float sequenceData = currentLineId + (currentLinePoint * 0.0001f);
        points[currentPointIndex] = new Vector4(
            newPosition.x,
            newPosition.y,
            Random.Range(minRadius, maxRadius),
            sequenceData
        );
        // Update the buffer
        deformBuffer.SetData(points);

        // Update tracking variables
        lastPosition = newPosition;
        currentLinePoint++;
        currentPointIndex = (currentPointIndex + 1) % MAX_DEFORM_POINTS;

        // If we still have points in this line, schedule the next one
        if (currentLinePoint < maxPointsPerLine)
        {
            
        }
        else
        {
            isDrawingLine = false;
        }
    }

    private void AddRandomPoint()
    {
        isDrawingLine = false;
        Vector2 randomPoint = new Vector2(
            Random.Range(objectBounds.min.x, objectBounds.max.x),
            Random.Range(objectBounds.min.z, objectBounds.max.z)
        );

        points[currentPointIndex] = new Vector4(
            randomPoint.x,
            randomPoint.y,
            Random.Range(minRadius, maxRadius),
            0  // 0 in w means it's not part of a line
        );

        deformBuffer.SetData(points);
        currentPointIndex = (currentPointIndex + 1) % MAX_DEFORM_POINTS;
    }

    // Enhanced visualization
    private void OnDrawGizmos()
    {
        if (points == null) return;

        for (int i = 0; i < points.Length; i++)
        {
            var point = points[i];
            if (point.z <= 0) continue; // Skip inactive points

            // Draw the point
            Gizmos.color = Color.red;
            Gizmos.DrawWireSphere(new Vector3(point.x, transform.position.y, point.y), point.z);

            // Draw lines between sequential points
            if (point.w > 0) // If it's part of a line
            {
                int currentId = Mathf.FloorToInt(point.w);
                float sequence = (point.w - currentId) * 10000;

                // Look for the next point in the sequence
                for (int j = 0; j < points.Length; j++)
                {
                    var nextPoint = points[j];
                    int nextId = Mathf.FloorToInt(nextPoint.w);
                    float nextSequence = (nextPoint.w - nextId) * 10000;

                    if (nextId == currentId && // Same line
                        Mathf.Abs(nextSequence - sequence) < 2 && // Sequential points
                        nextSequence > sequence) // Next in sequence
                    {
                        Gizmos.color = Color.yellow;
                        Gizmos.DrawLine(
                            new Vector3(point.x, transform.position.y, point.y),
                            new Vector3(nextPoint.x, transform.position.y, nextPoint.y)
                        );
                        break;
                    }
                }
            }
        }
    }
}