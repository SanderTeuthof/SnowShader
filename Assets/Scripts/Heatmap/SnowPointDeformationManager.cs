using System.Collections.Generic;
using UnityEngine;

public class SnowPointDeformationManager : MonoBehaviour
{
    public static SnowPointDeformationManager Instance { get; private set; }

    [SerializeField] private Material snowMaterial;

    private ComputeBuffer deformBuffer;
    private const int MAX_DEFORM_POINTS = 20;
    private Vector4[] points;
    private int currentPointIndex;
    private int currentLineId = 1;
    private Dictionary<int, bool> activeLines = new Dictionary<int, bool>();

    private void Awake()
    {
        if (Instance != null && Instance != this)
        {
            Destroy(gameObject);
            return;
        }
        Instance = this;

        InitializeBuffer();
    }

    private void InitializeBuffer()
    {
        points = new Vector4[MAX_DEFORM_POINTS];
        deformBuffer = new ComputeBuffer(MAX_DEFORM_POINTS, 4 * sizeof(float));

        for (int i = 0; i < MAX_DEFORM_POINTS; i++)
        {
            points[i] = new Vector4(0, 0, 0, 0);
        }

        snowMaterial.SetBuffer("_DeformPoints", deformBuffer);
        snowMaterial.SetInt("_NumDeformPoints", MAX_DEFORM_POINTS);
        deformBuffer.SetData(points);
    }

    public int StartNewLine()
    {
        int lineId = currentLineId++;
        activeLines[lineId] = true;
        return lineId;
    }

    public void EndLine(int lineId)
    {
        if (activeLines.ContainsKey(lineId))
        {
            activeLines.Remove(lineId);
        }
    }

    public void AddLinePoint(int lineId, Vector3 worldPosition, float radius)
    {
        if (!activeLines.ContainsKey(lineId))
            return;

        float sequenceData = lineId + (Time.time * 0.0001f); // Use time for sequence instead of point count

        points[currentPointIndex] = new Vector4(
            worldPosition.x,
            worldPosition.z,
            radius,
            sequenceData
        );

        deformBuffer.SetData(points);
        currentPointIndex = (currentPointIndex + 1) % MAX_DEFORM_POINTS;
    }

    public void AddSinglePoint(Vector3 worldPosition, float radius)
    {
        points[currentPointIndex] = new Vector4(
            worldPosition.x,
            worldPosition.z,
            radius,
            0  // 0 in w means it's not part of a line
        );

        deformBuffer.SetData(points);
        currentPointIndex = (currentPointIndex + 1) % MAX_DEFORM_POINTS;
    }

    private void OnDestroy()
    {
        if (deformBuffer != null)
        {
            deformBuffer.Release();
            deformBuffer = null;
        }
    }
}
