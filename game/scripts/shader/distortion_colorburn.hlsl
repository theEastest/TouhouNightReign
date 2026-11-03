// Reference distortion, with finite normalization/power at the effect center.
Texture2D screen_texture : register(t4);
SamplerState screen_texture_sampler : register(s4);
cbuffer engine_data : register(b1) { float4 screen_texture_size; float4 viewport; };
cbuffer user_data : register(b0) {
    float centerX; float centerY; float size; float arg;
    float4 color;
    float colorsize; float timer;
};
float4 main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target
{
    float2 xy=uv*screen_texture_size.xy;
    float2 delta=xy-float2(centerX,centerY);
    float len=length(delta);
    float2 direction=delta/max(len,0.0001);
    float2 uv2=uv;
    if (size>0 && len<=size) {
        float strength=arg*pow(saturate(1-len/size),.75);
        float2 wave=sin(1.75*6.2831853*direction+.05*len+float2(timer/5,timer/6));
        float2 offset=wave*strength*sin(.005*6.2831853*len+timer/10);
        float2 result=xy+offset;
        if (all(result>viewport.xy+5) && all(result<viewport.zw-5)) uv2+=offset/screen_texture_size.xy;
    }
    float4 c=screen_texture.Sample(screen_texture_sampler,uv2);
    if (colorsize>0 && len<=colorsize) {
        float blend=color.a*pow(saturate(1-len/colorsize),1.2);
        float3 pigment=max(50.0/255,color.rgb);
        c.rgb=lerp(c.rgb,c.rgb-(1-c.rgb)*(1-pigment)/pigment,blend);
    }
    c.a=1;return c;
}
