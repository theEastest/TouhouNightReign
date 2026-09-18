// 由PostEffect过程捕获到的纹理
texture2D ScreenTexture:POSTEFFECTTEXTURE;  // 纹理
sampler2D ScreenTextureSampler = sampler_state {  // 采样器
    texture = <ScreenTexture>;
    AddressU  = BORDER;
    AddressV = BORDER;
    Filter = MIN_MAG_LINEAR_MIP_POINT;
};

// 自动设置的参数
float4 screen : SCREENSIZE;  // 屏幕缓冲区大小

// 外部参数
texture2D Texture2 < string binding = "tex"; >;
sampler2D ScreenTextureSampler2 = sampler_state {  // 采样器
    texture = <Texture2>;
    AddressU  = BORDER;
    AddressV = BORDER;
    Filter = MIN_MAG_LINEAR_MIP_POINT;
};

float4 PS_MainPass(float4 position:POSITION, float2 uv:TEXCOORD0):COLOR
{	 
    // 对纹理进行采样
    float4 texColor = tex2D(ScreenTextureSampler, uv);
    float4 texColor2 = tex2D(ScreenTextureSampler2, uv);
    if (texColor2.r!=0 && texColor2.g!=0 && texColor2.b!=0) {
	texColor.a = (1 + texColor2.a) / 2;
	texColor.r = texColor2.a * texColor.r;
	texColor.g = texColor2.a * texColor.g;
	texColor.b = texColor2.a * texColor.b;
   	 }
	else
	texColor.a = 0;
    //texColor.a = 1;
    return texColor;
}

technique Main
{
    pass MainPass
    {
        PixelShader = compile ps_3_0 PS_MainPass();
    }
}
