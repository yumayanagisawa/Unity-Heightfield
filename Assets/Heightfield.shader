// Based on video heightfield by simesgreen https://www.shadertoy.com/view/Xss3zr
Shader "Unlit/Heightfield"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
		iChannel0("Texture", 2D) = "white" {}
		_ax("ax for test", Float) = -0.7
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

			sampler2D iChannel0;
			float _ax;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

			static const int _Steps = 256;
			static const float3 lightDir = float3(0.577, 0.577, 0.577);

			// transforms
			float3 rotateX(float3 p, float a) {
				float sa = sin(a);
				float ca = cos(a);
				float3 r;
				r.x = p.x;
				r.y = ca * p.y - sa * p.z;
				r.z = sa * p.y + ca * p.z;
				return r;
			}

			float3 rotateY(float3 p, float a) {
				float sa = sin(a);
				float ca = cos(a);
				float3 r;
				r.x = ca * p.x + sa * p.z;
				r.y = p.y;
				r.z = -sa * p.x + ca * p.z;
				return r;
			}

			bool intersectBox(float3 ro, float3 rd, float3 boxmin, float3 boxmax, out float tnear, out float tfar) {
				// testing animation
				boxmax.y = sin(_Time.y);
				// compute intersection of ray with all six bbox planes
				float3 invR = 1.0 / rd;
				float3 tbot = invR * (boxmin - ro);
				float3 ttop = invR * (boxmax - ro);
				// re-order intersections to find smallest and largest on each axis
				float3 tmin = min(ttop, tbot);
				float3 tmax = max(ttop, tbot);
				// find the largest tmin and the smallest tmax
				float2 t0 = max(tmin.xx, tmin.yz);
				tnear = max(t0.x, t0.y);
				t0 = min(tmax.xx, tmax.yz);
				tfar = min(t0.x, t0.y);
				// check for hit
				bool hit;
				if ((tnear > tfar)) {
					hit = false;
				}
				else {
					hit = true;
				}
				return hit;
			}

			float luminance(sampler2D tex, float2 uv) {
				// tex2Dlod seems unnecessary
				//float3 c = tex2Dlod(tex, position).xyz;
				float3 c = tex2D(tex, uv).xyz;
				return dot(c, float3(0.33, 0.33, 0.33));
			}

			float2 gradient(sampler2D tex, float2 uv, float2 texelSize) {
				float h = luminance(tex, uv);
				float hx = luminance(tex, uv + texelSize * float2(1.0, 0.0));
				float hy = luminance(tex, uv + texelSize * float2(0.0, 1.0));
				return float2(hx - h, hy - h);
			}

			float2 worldToTex(float3 p) {
				float2 uv = p.xz*0.5 + 0.5;
				uv.y = 1.0 - uv.y;
				return uv;
			}

			float heightField(float3 p) {
				return luminance(iChannel0, worldToTex(p))*0.5;
			}

			bool traceHeightField(float3 ro, float3 rayStep, out float3 hitPos) {
				float3 p = ro;
				bool hit = false;
				float pH = 0.0;
				float3 pP = p;
				for (int i = 0; i < _Steps; i++) {
					float h = heightField(p);
					if ((p.y < h) && !hit) {
						hit = true;
						//hitPos = p;
						// interpolate based on height
						hitPos = lerp(pP, p, (pH - pP.y) / ((p.y - pP.y) - (h - pH)));
					}
					pH = h;
					pP = p;
					p += rayStep;
				}
				return hit;
			}

			float3 background(float3 rd) {
				return lerp(float3(1.0, 1.0, 1.0), float3(0.2, 0.2, 0.2), abs(rd.y));
			}

            fixed4 frag (v2f i) : SV_Target
            {
				float2 pixel = (i.uv.xy*2.0) -1.0;

				// compute ray origin and direction
				float asp = _ScreenParams.x / _ScreenParams.y;
				float3 rd = normalize(float3(asp*pixel.x, pixel.y, -2.0));
				float3 ro = float3(0.0, 0.0, 2.0); // var type was wrong...

				float2 mouse = float2(0.0, 0.0); // for now

				// rotate view
				float ax = _ax;// todo testing -1.7;

				rd = rotateX(rd, ax);
				ro = rotateX(ro, ax);

				float ay = _Time.y;// sin(_Time.y);
				rd = rotateY(rd, ay);
				ro = rotateY(ro, ay);

				// intersect with bounding box
				bool hit;
				//static const float3 boxMin = float3(-1.0, -0.01, -1.0);
				static const float3 boxMin = float3(-1.0, -0.01, -1.0);
				static const float3 boxMax = float3(1.0, 0.5, 1.0);
				
				float tnear, tfar;
				hit = intersectBox(ro, rd, boxMin, boxMax, tnear, tfar);

				tnear -= 0.0001;
				float3 pnear = ro + rd * tnear;
				float3 pfar = ro + rd * tfar;

				float stepSize = length(pfar - pnear) / float(_Steps);

				float3 rgb = background(rd);
				if (hit)
				{
					// intersect with heightfield
					ro = pnear;
					float3 hitPos;// = float3(0.0, 0.0, 0.0);
					hit = traceHeightField(ro, rd*stepSize, hitPos);
					if (hit)
					{
						float2 uv = worldToTex(hitPos);
						rgb = tex2D(iChannel0, uv).xyz;
#if 0
						hitPos += float3(0.0, 0.01, 0.0);
						bool shadow = traceHeightField(hitPos, lightDir*0.01, hitPos);
						if (shadow)
						{
							rgb *= 0.75;
						}
#endif
					}
				}
				return float4(rgb, 1.0);
            }
            ENDCG
        }
    }
}
