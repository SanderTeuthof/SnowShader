using UnityEngine;

public class AddForceInRandomDirection : MonoBehaviour
{
    [SerializeField]
    private float forceMagnitude = 10f; // Adjustable force magnitude

    private Rigidbody rb;

    private Vector3 _randDirection;

    private void Awake()
    {
        Vector2 randomDirection2D = Random.insideUnitCircle.normalized;
        _randDirection = new Vector3(randomDirection2D.x, 0, randomDirection2D.y);
        rb = GetComponent<Rigidbody>();
    }

    private void Start()
    {
        if (rb != null)
        {
            ApplyRandomForce();
        }
    }

    private void ApplyRandomForce()
    {

        // Apply force to the Rigidbody
        rb.AddForce(_randDirection * forceMagnitude, ForceMode.Impulse);
    }
}
