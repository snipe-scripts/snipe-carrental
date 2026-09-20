using System.Numerics;

namespace PropBuilder;

public readonly record struct PropVertex(Vector3 Position, Vector3 Normal, Vector2 Uv, uint ColorRgba);
public enum MaterialAlpha { Opaque, Mask, Blend }
public sealed class PropGeometry
{
    public required string MaterialName { get; init; }
    public byte[]? BaseColorImage { get; set; }
    public string? ImageExtension { get; set; }
    public MaterialAlpha AlphaMode { get; set; }
    public bool DoubleSided { get; set; }
    public List<PropVertex> Vertices { get; } = new();
    public List<int> Indices { get; } = new();
}
public sealed class PropModel
{
    public required List<PropGeometry> Geometries { get; init; }
    public Vector3 BoxMin { get; init; }
    public Vector3 BoxMax { get; init; }
    public Vector3 Center => (BoxMin + BoxMax) * 0.5f;
    public float Radius => Vector3.Distance(Center, BoxMax);
    public int TriangleCount => Geometries.Sum(g => g.Indices.Count / 3);
    public int VertexCount => Geometries.Sum(g => g.Vertices.Count);
}

internal sealed class Mesh
{
    private readonly Dictionary<string, PropGeometry> groups = new();
    private Vector3 min = new(float.MaxValue), max = new(float.MinValue);
    public PropModel Finish() => new() { Geometries = groups.Values.ToList(), BoxMin = min, BoxMax = max };

    public void Triangle(string material, Vector3 a, Vector3 b, Vector3 c, uint color = 0xFFFFFFFF)
    {
        var cross = Vector3.Cross(b - a, c - a);
        if (cross.LengthSquared() < 1e-14f) return;
        if (!groups.TryGetValue(material, out var geometry))
            groups[material] = geometry = new PropGeometry { MaterialName = material,
                AlphaMode = material == "glass" ? MaterialAlpha.Blend : MaterialAlpha.Opaque };
        var normal = Vector3.Normalize(cross);
        foreach (var point in new[] { a, b, c })
        {
            var uv = Math.Abs(normal.Z) > 0.5f ? new Vector2(point.X, point.Y) :
                Math.Abs(normal.Y) > 0.5f ? new Vector2(point.X, point.Z) : new Vector2(point.Y, point.Z);
            geometry.Indices.Add(geometry.Vertices.Count);
            geometry.Vertices.Add(new PropVertex(point, normal, uv, color));
            min = Vector3.Min(min, point); max = Vector3.Max(max, point);
        }
    }

    public void Quad(string material, Vector3 a, Vector3 b, Vector3 c, Vector3 d, uint color = 0xFFFFFFFF)
    { Triangle(material, a, b, c, color); Triangle(material, a, c, d, color); }

    public void Screen(float x, float y, float z, float width, float height)
    {
        if (!groups.TryGetValue("screen", out var g)) groups["screen"] = g = new PropGeometry { MaterialName = "screen" };
        var start=g.Vertices.Count;
        Vector3[] points={new(x-width/2,y,z-height/2),new(x+width/2,y,z-height/2),new(x+width/2,y,z+height/2),new(x-width/2,y,z+height/2)};
        Vector2[] uv={new(0,1),new(1,1),new(1,0),new(0,0)};
        for(var i=0;i<4;i++)
        {
            g.Vertices.Add(new PropVertex(points[i],new Vector3(0,-1,0),uv[i],0xFFFFFFFF));
            min=Vector3.Min(min,points[i]);max=Vector3.Max(max,points[i]);
        }
        foreach(var index in new[]{0,1,2,0,2,3})g.Indices.Add(start+index);
    }

    public void Box(string material, float x, float y, float z, float width, float depth, float height, uint color = 0xFFFFFFFF)
    {
        var x0 = x - width / 2; var x1 = x + width / 2;
        var y0 = y - depth / 2; var y1 = y + depth / 2;
        Vector3[] v = { new(x0,y0,z), new(x1,y0,z), new(x1,y1,z), new(x0,y1,z),
            new(x0,y0,z+height), new(x1,y0,z+height), new(x1,y1,z+height), new(x0,y1,z+height) };
        int[][] faces = { new[]{3,2,1,0}, new[]{4,5,6,7}, new[]{0,1,5,4}, new[]{1,2,6,5}, new[]{2,3,7,6}, new[]{3,0,4,7} };
        foreach (var f in faces) Quad(material, v[f[0]], v[f[1]], v[f[2]], v[f[3]], color);
    }

    private static List<Vector2> RoundedRing(float width, float depth, float radius)
    {
        List<Vector2> ring = new();
        for (var corner = 0; corner < 4; corner++)
        {
            var angle = corner * MathF.PI / 2;
            var cx = corner is 0 or 3 ? width / 2 - radius : -width / 2 + radius;
            var cy = corner < 2 ? depth / 2 - radius : -depth / 2 + radius;
            for (var segment = 0; segment <= 5; segment++)
            {
                var theta = angle + segment * MathF.PI / 10;
                ring.Add(new Vector2(cx + radius * MathF.Cos(theta), cy + radius * MathF.Sin(theta)));
            }
        }
        return ring;
    }

    // Horizontal closed rounded slab, with sloped edges when lower/upper sizes differ.
    public void Slab(string material, float width, float depth, float radius, float z, float height,
        float upperInset = 0, float x = 0, float y = 0, uint color = 0xFFFFFFFF)
    {
        var lower = RoundedRing(width, depth, radius);
        var upper = RoundedRing(width - 2 * upperInset, depth - 2 * upperInset, Math.Max(0.01f, radius - upperInset));
        for (var i = 0; i < lower.Count; i++)
        {
            var n = (i + 1) % lower.Count;
            var a = new Vector3(lower[i].X+x,lower[i].Y+y,z);
            var b = new Vector3(lower[n].X+x,lower[n].Y+y,z);
            var c = new Vector3(upper[n].X+x,upper[n].Y+y,z+height);
            var d = new Vector3(upper[i].X+x,upper[i].Y+y,z+height);
            Quad(material,a,b,c,d,color);
            Triangle(material,new Vector3(x,y,z),b,a,color);
            Triangle(material,new Vector3(x,y,z+height),d,c,color);
        }
    }

    public void RoundedStrip(string material, float width, float depth, float radius, float z, float height, float thickness)
    {
        var outer = RoundedRing(width,depth,radius);
        var inner = RoundedRing(width-thickness*2,depth-thickness*2,Math.Max(.01f,radius-thickness));
        for (var i=0;i<outer.Count;i++)
        {
            var j=(i+1)%outer.Count;
            Vector3 P(Vector2 point,float h) => new(point.X,point.Y,h);
            Quad(material,P(outer[i],z),P(outer[j],z),P(outer[j],z+height),P(outer[i],z+height));
            Quad(material,P(inner[j],z),P(inner[i],z),P(inner[i],z+height),P(inner[j],z+height));
            Quad(material,P(outer[i],z+height),P(outer[j],z+height),P(inner[j],z+height),P(inner[i],z+height));
        }
    }

    public void Cylinder(string material, float x, float y, float z, float radius, float height, uint color = 0xFFFFFFFF, int count = 16)
    {
        for(var i=0;i<count;i++)
        {
            var a=i*2*MathF.PI/count; var b=(i+1)*2*MathF.PI/count;
            Vector3 p = new(x+radius*MathF.Cos(a),y+radius*MathF.Sin(a),z);
            Vector3 q = new(x+radius*MathF.Cos(b),y+radius*MathF.Sin(b),z);
            var top = new Vector3(0,0,height);
            Quad(material,p,q,q+top,p+top,color);
            Triangle(material,new(x,y,z),q,p,color);
            Triangle(material,new(x,y,z+height),p+top,q+top,color);
        }
    }

    public void Capsule(float x, float y, float z)
    {
        const int segments=16;
        const float half=.13f, radius=.095f;
        var sections=new List<Vector2>();
        for(var i=0;i<=6;i++) {var p=i*MathF.PI/12;sections.Add(new(half+radius*MathF.Cos(p),radius*MathF.Sin(p)));}
        sections.Add(new(0,radius));
        for(var i=6;i<=12;i++) {var p=i*MathF.PI/12;sections.Add(new(-half+radius*MathF.Cos(p),radius*MathF.Sin(p)));}
        Vector3 Point(int ring,int segment)
        {
            var theta=segment*2*MathF.PI/segments;
            return new(x+sections[ring].X,y+sections[ring].Y*MathF.Cos(theta),z+sections[ring].Y*MathF.Sin(theta));
        }
        for(var ring=0;ring<sections.Count-1;ring++)
            for(var s=0;s<segments;s++)
                Quad(sections[ring].X>0 ? "accent" : "ceramic",Point(ring,s),Point(ring+1,s),Point(ring+1,s+1),Point(ring,s+1));
    }
}
