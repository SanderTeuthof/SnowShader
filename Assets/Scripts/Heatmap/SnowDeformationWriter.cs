using UnityEngine;

[RequireComponent(typeof(SphereCollider))]
public class SnowDeformationWriter : MonoBehaviour
{
    [SerializeField] private LayerMask snowSurfaceLayer;
    [SerializeField] private float minDistanceBetweenPoints = 0.1f;

    private int currentLineId = -1;
    private Vector3 lastPointPosition;
    private bool hasLastPosition;
    private SphereCollider sphereCollider;

    private void Awake()
    {
        sphereCollider = GetComponent<SphereCollider>();
    }

    private void OnCollisionEnter(Collision collision)
    {
        if ((snowSurfaceLayer.value & (1 << collision.gameObject.layer)) != 0)
        {
            currentLineId = SnowPointDeformationManager.Instance.StartNewLine();
            hasLastPosition = false;
        }
    }

    private void OnCollisionStay(Collision collision)
    {
        if ((snowSurfaceLayer.value & (1 << collision.gameObject.layer)) == 0)
            return;

        var contactPoint = collision.GetContact(0);

        if (!hasLastPosition)
        {
            // First point in the line
            AddPoint(contactPoint.point);
            return;
        }

        float distanceFromLast = Vector3.Distance(contactPoint.point, lastPointPosition);
        if (distanceFromLast >= minDistanceBetweenPoints)
        {
            AddPoint(contactPoint.point);
        }
    }

    private void AddPoint(Vector3 position)
    {
        float radius = sphereCollider.radius * transform.lossyScale.x;
        SnowPointDeformationManager.Instance.AddLinePoint(currentLineId, position, radius);
        lastPointPosition = position;
        hasLastPosition = true;
    }

    private void OnCollisionExit(Collision collision)
    {
        if ((snowSurfaceLayer.value & (1 << collision.gameObject.layer)) != 0)
        {
            if (currentLineId != -1)
            {
                SnowPointDeformationManager.Instance.EndLine(currentLineId);
                currentLineId = -1;
            }
        }
    }
}
