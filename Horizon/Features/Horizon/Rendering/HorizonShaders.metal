#include <metal_stdlib>
using namespace metal;
struct Frame {
    float4x4 vp;
    float4 eye;
    float4 motion; // time, journey, formation, rotation
    float4 viewport; // pixel scale, particle stride, guide globe brightness (0 disables), reserved
    float4 interaction; // normalized user quaternion, xyzw
    float4 globe; // world-space center xyz, radius w
    float4 introduction; // wall construction, particle visibility, brick scale, aspect
    float4 scatter; // shared atmosphere center xyz, scale w (guide camera framing)
};
struct WallOut {
    float4 position [[position]];
    float fade;
    float2 uv [[sample_perspective]];
    uint outlined [[flat]];
    float assembly [[flat]];
    float touchHighlight [[flat]];
};
vertex WallOut horizon_wall(uint id [[vertex_id]], const device float4 *v [[buffer(0)]], constant Frame &f [[buffer(1)]], const device float4 *touch [[buffer(2)]]) {
    float3 p=v[id].xyz;
    WallOut o;
    o.assembly=1; o.touchHighlight=0;
    if(id>=6 && f.introduction.x>=1) {
        float4 feedback=touch[(id-6)/36];
        p.z+=feedback.x;
        o.touchHighlight=feedback.y;
    }
    if(f.introduction.x<1) {
        if(id<6) {
            // The full mortar backing must not hide the world before the bricks exist.
            o.assembly=0;
        } else {
            uint brick=(id-6)/36, base=6+brick*36;
            float3 center=(v[base].xyz+v[base+2].xyz)*0.5;
            center.z=0;
            float scale=clamp(f.introduction.z,1.0,3.0);
            float rows=ceil(18.0/scale);
            float row=floor(center.y/(0.17*scale));
            // Sequence the on-screen bricks, not hundreds of off-screen columns.
            // The reference camera stays fixed even when Skip starts the return journey.
            float halfWidth=max(0.35,4.5*tan(55.0*M_PI_F/360.0)*f.introduction.w);
            float column=clamp((center.x/halfWidth+1.0)*0.5,0.0,1.0);
            if(uint(row)%2==1) column=1.0-column;
            float start=0.60*row/max(1.0,rows-1.0)+0.32*column;
            o.assembly=smoothstep(start,start+0.08,f.introduction.x);
            p=center+(p-center)*o.assembly;
            p.y-=(1-o.assembly)*0.18;
        }
    }
    o.position=f.vp*float4(p,1);
    // Geometry emits each quad as [0,1,2,0,2,3]. Quad UVs avoid drawing
    // the triangle diagonal; the first quad is the unoutlined mortar backing.
    constexpr float2 corners[6] = {float2(0,0),float2(1,0),float2(1,1),
                                 float2(0,0),float2(1,1),float2(0,1)};
    o.uv=corners[id%6]; o.outlined=id>=6;
    o.fade=clamp(5.0/length(f.eye.xyz-p),0.16,1.0);
    return o;
}
fragment float4 horizon_wall_color(WallOut v [[stage_in]]) {
    if(v.assembly<=0.001) discard_fragment();
    // Pixel-space distance to the four face edges. Evaluate at MSAA samples
    // and feather coverage rather than rasterizing separate one-pixel lines.
    float2 dx=dfdx(v.uv), dy=dfdy(v.uv);
    float2 pixelGradient=max(sqrt(dx*dx+dy*dy),float2(1e-6));
    float2 distance=min(v.uv,1.0-v.uv)/pixelGradient;
    // Fade in from the actual face boundary as well as out toward its interior.
    // A bright discontinuity right at the silhouette would still flicker as the
    // four MSAA coverage samples cross it. This band has no such hard endpoint.
    float2 bands=smoothstep(0.0,0.75,distance)*(1.0-smoothstep(0.75,2.25,distance));
    float edge=max(bands.x,bands.y)*float(v.outlined);
    return float4(float3(mix(0.008,mix(0.78,1.0,v.touchHighlight),edge)*v.fade*v.assembly),1);
}
float hash(float n) { return fract(sin(n*127.1+311.7)*43758.5453); }
struct DotOut { float4 position [[position]]; float size [[point_size]]; float alpha; };
vertex DotOut horizon_particle(uint rawID [[vertex_id]], const device float4 *points [[buffer(0)]], constant Frame &f [[buffer(1)]]) {
    uint id=rawID*uint(f.viewport.y);
    float seed=float(id)+1;
    float4 data=points[id];
    float ambient=data.w<0 ? 1.0 : 0.0;
    float t=f.motion.x, form=f.motion.z*(1.0-ambient), angle=f.motion.w;
    float3 n=data.xyz;
    float3 normal=float3(cos(angle)*n.x+sin(angle)*n.z,n.y,-sin(angle)*n.x+cos(angle)*n.z);
    float3 q=f.interaction.xyz;
    normal+=2.0*cross(q,cross(q,normal)+f.interaction.w*normal);
    float3 center=f.globe.xyz;
    float3 scatter=f.scatter.xyz+float3((hash(seed)-.5)*13,(hash(seed+31)-.5)*7.5,(hash(seed+71)-.5)*7)*f.scatter.w;
    scatter+=float3(sin(t*.19+seed)*.22,cos(t*.16+seed*.3)*.24,sin(t*.12+seed*.7)*.2)*f.scatter.w;
    float3 world=mix(scatter,center+normal*f.globe.w,form);
    // Shared paths add a small curl during assembly, vanishing at both endpoints.
    world+=float3(sin(seed+t*.3),cos(seed*.7+t*.2),sin(seed*.2))*(form*(1-form)*.42);
    float front=smoothstep(-.06,.28,dot(normal,normalize(f.eye.xyz-center)));
    float alpha=mix(.16+.3*hash(seed+9),max(.12,data.w)*front,form);
    alpha*=mix(.15,1.0,smoothstep(.35,.94,f.motion.y));
    if(ambient>0) alpha*=.32;
    alpha*=f.introduction.y;
    DotOut o; o.position=f.vp*float4(world,1);
    o.size=clamp((data.w>.5 ? 1.25 : 1.0)*f.viewport.x*9.0/max(3.0,o.position.w),1.0,5.0*f.viewport.x);
    // Only the guide globe dims slightly; original point sizes and atmosphere
    // remain untouched. Brightness converges to 1 before the matched handoff.
    if(ambient==0 && f.viewport.z>0) alpha*=f.viewport.z;
    o.alpha=alpha;
    return o;
}
fragment float4 horizon_particle_color(DotOut v [[stage_in]], float2 coord [[point_coord]]) {
    float d=length(coord*2-1);
    if(d>1) discard_fragment();
    float alpha=(1-smoothstep(.12,1.0,d))*v.alpha;
    return float4(1,1,1,alpha);
}
