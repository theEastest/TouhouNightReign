// D3D11 port of activity7/er_desaturate.fx.
// LuaSTG binds the first PostEffect argument as screen_texture and the
// legacy { tex = "er_desaturate_b" } argument by the texture variable name.
Texture2D screen_texture : register(t4);
SamplerState screen_texture_sampler : register(s4);
Texture2D tex : register(t0);
SamplerState tex_sampler : register(s0);

float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 color = screen_texture.Sample(screen_texture_sampler, uv);
    float3 mask = tex.Sample(tex_sampler, uv).rgb;
    // Preserve the original RGB mask test and luminance weights exactly.
    if (mask.r != 0.0 && mask.g != 0.0 && mask.b != 0.0)
    {
        float gray = dot(color.rgb, float3(0.30, 0.59, 0.11));
        color.rgb = gray.xxx;
    }
    color.a = 1.0;
    return color;
}
