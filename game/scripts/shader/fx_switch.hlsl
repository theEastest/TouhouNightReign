Texture2D screen_texture : register(t4);
SamplerState screen_texture_sampler : register(s4);
Texture2D tex : register(t0);
SamplerState tex_sampler : register(s0);
float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = screen_texture.Sample(screen_texture_sampler, uv);
    float4 mask = tex.Sample(tex_sampler, uv);
    if (all(mask.rgb != 0)) { c.rgb *= mask.a; c.a = (1 + mask.a)/2; }
    else c.a = 0;
    return c;
}
