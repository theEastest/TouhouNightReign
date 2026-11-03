// D3D11 port of the reference cameo.fx, preserving its mask and emboss kernel.
Texture2D screen_texture : register(t4);
SamplerState screen_texture_sampler : register(s4);
Texture2D tex : register(t0);
SamplerState tex_sampler : register(s0);
float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float4 c = screen_texture.Sample(screen_texture_sampler, uv);
    float3 mask = tex.Sample(tex_sampler, uv).rgb;
    float dist = c.r + c.g + c.b;
    if (all(mask != 0)) {
        float3 delta = c.rgb - screen_texture.Sample(screen_texture_sampler, uv - float2(dist/640, dist/480)).rgb;
        c.rgb = dot(delta, float3(.30,.59,.11)) + float3(.55,.4,.3);
    }
    c.a = 1;
    return c;
}
