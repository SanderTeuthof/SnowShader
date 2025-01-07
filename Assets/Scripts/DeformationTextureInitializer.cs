using UnityEngine;

[RequireComponent(typeof(MeshRenderer))]
public class DeformationTextureInitializer : MonoBehaviour
{
    private void Awake()
    {
        MeshRenderer renderer = GetComponent<MeshRenderer>();
        Material material = renderer.material;

        // Get values from material
        RenderTexture deformationTexture = material.GetTexture("_DeformationTexture") as RenderTexture;
        float standardValue = material.GetFloat("_TextureStandardValue");

        if (deformationTexture != null)
        {
            
            RenderTexture tempRT = RenderTexture.GetTemporary(
                deformationTexture.width,
                deformationTexture.height,
                0,
                deformationTexture.format
            );

            // Fill the texture with the standard value
            RenderTexture currentRT = RenderTexture.active;
            RenderTexture.active = tempRT;
            GL.Clear(true, true, new Color(standardValue, standardValue, standardValue, standardValue));
            RenderTexture.active = currentRT;

            // Copy to the actual deformation texture
            Graphics.Blit(tempRT, deformationTexture);
            RenderTexture.ReleaseTemporary(tempRT);
        }
    }
}