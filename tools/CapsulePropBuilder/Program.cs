using System.Globalization;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Xml;
using CodeWalker.GameFiles;
using ImageMagick;
using PropBuilder;

internal static class Program
{
    private const string DictionaryName = "snipe_capsule_txd_v1";
    private const string PaletteName = "snipe_capsule_tint_palette";
    private const string ReferenceRoot = "D:/qbox_new/txData/QboxProject_C63A32.base/resources/[alphabets]/glowglyphs";
    private static readonly Dictionary<string,string> TextureNames = new()
    {
        ["body"]="snipe_capsule_body", ["deck"]="snipe_capsule_deck", ["metal"]="snipe_capsule_metal",
        ["accent"]="snipe_capsule_accent", ["screen"]="snipe_capsule_screen_d", ["ceramic"]="snipe_capsule_ceramic",
        ["glass"]="snipe_capsule_glass",
    };

    public static int Main(string[] args)
    {
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.InvariantCulture;
            RpfManager.IsGen9 = false;
            var output = Path.GetFullPath(args.Length > 0 ? args[0] : "artifacts/props-candidate");
            var stream = Path.Combine(output,"stream");
            Directory.CreateDirectory(stream);
            Directory.CreateDirectory(Path.Combine(output,"xml"));
            var models = new Dictionary<string,PropModel>
            {
                ["snipe_capsule_platform_v1"]=Platform(),
                ["snipe_capsule_deck_v2"]=Platform(true,false),
                ["snipe_capsule_canopy_v2"]=Platform(false,true),
                ["snipe_capsule_shell_v2"]=WallShell(),
                ["snipe_capsule_tablet_v1"]=Tablet(),
                ["snipe_capsule_booth_v1"]=Booth(),
            };
            var ytd = BuildTextures(output);
            File.WriteAllBytes(Path.Combine(stream,DictionaryName+".ytd"),ytd.Save());
            var records = new List<object>();
            foreach (var (name,model) in models)
            {
                var bytes = BuildDrawable(name,model,output);
                File.WriteAllBytes(Path.Combine(stream,name+".ydr"),bytes);
                var archetypeBytes = IsMovingPart(name)
                    ? YtypBuilder.BuildCollisionlessPack(name,DictionaryName,new[]{(name,model)},120f)
                    : YtypBuilder.Build(name,DictionaryName,model,120f);
                File.WriteAllBytes(Path.Combine(stream,name+".ytyp"),archetypeBytes);
                records.Add(Validate(name,model,bytes,archetypeBytes,ytd,output));
                SaveObj(model,Path.Combine(output,name+".obj"));
                RenderPreview(model,Path.Combine(output,name+".png"));
                Console.WriteLine($"PASS {name}: {model.VertexCount} vertices, {model.TriangleCount} triangles, min={model.BoxMin}, max={model.BoxMax}");
            }
            var referenceYtdPath=Path.Combine(ReferenceRoot,"stream/glowglyphs_txd_v4.ytd");
            var report = new
            {
                generatedAtUtc=DateTime.UtcNow, status="structural_validation_passed",
                runtimeValidation="NOT RUN: FiveM collision, tint and DUI visual smoke tests required",
                type="standalone static props; not an MLO, no rooms, portals, YMAP, YMF or external YBN needed",
                reference=new { textureDictionary=referenceYtdPath, sha256=Hash(File.ReadAllBytes(referenceYtdPath)),
                    pattern="emissive_tnt.sps + 256x16 uncompressed TINTPALETTE, X64 | UNK24, zero mipmaps" },
                palette=JsonDocument.Parse(File.ReadAllText(Path.Combine(ReferenceRoot,"glyph_manifest.json"))).RootElement.GetProperty("variations").Clone(),
                screenPlanes=new {
                    tablet=new { centre=new[]{0f,-.081f,1.39f}, normal=new[]{0f,-1f,0f}, width=.56f,height=.84f },
                    booth=new { centre=new[]{.645f,-.326f,1.35f}, normal=new[]{0f,-1f,0f}, width=.42f,height=.63f } },
                platform=new { groundOrigin=new[]{0,0,0}, deckHeight=.13f, roofUnderside=3.23f,
                    clearInnerWidth=4.04f, clearInnerLength=5.94f, vehicleSpawnHeightOffset=.20f },
                animation=new { deck="snipe_capsule_deck_v2",canopy="snipe_capsule_canopy_v2",shell="snipe_capsule_shell_v2",
                    raisedOffsetZ=0f,retractedOffsetZ=-3.50f,movingPartsCollision=false,deckCollision=true },
                models=records,
            };
            File.WriteAllText(Path.Combine(output,"validation.json"),JsonSerializer.Serialize(report,new JsonSerializerOptions {WriteIndented=true}));
            return 0;
        }
        catch(Exception ex)
        {
            Console.Error.WriteLine(ex.ToString());
            return 1;
        }
    }

    private static bool IsMovingPart(string name)=>name is "snipe_capsule_canopy_v2" or "snipe_capsule_shell_v2";

    private static PropModel Platform(bool includeDeck=true,bool includeCanopy=true)
    {
        var m=new Mesh();
        // Ground-origin chamfered deck. Its ramped edge is real collision geometry.
        if(includeDeck)
        {
            m.Slab("deck",4.76f,7.36f,.20f,0,.13f,.16f);
            m.RoundedStrip("accent",4.49f,7.09f,.12f,.117f,.035f,.045f);
            m.Slab("deck",4.30f,6.90f,.07f,.13f,.006f);
        }
        // Floor access-panel seams, wheel landing zones and side traction plates.
        for(var side=-1;side<=1;side+=2)
        {
            if(includeDeck)
            {
                m.Box("body",side*1.72f,0,.137f,.065f,5.85f,.003f);
                m.Box("metal",side*.90f,0,.137f,.38f,5.25f,.006f,0x999999FF);
                for(var row=-8;row<=8;row++)
                    m.Box("body",side*.9f,row*.28f,.144f,.38f,.013f,.003f);
            }
            if(!includeCanopy)continue;
            for(var end=-1;end<=1;end+=2)
            {
                var x=side*2.11f;var y=end*3.04f;
                m.Box("body",x,y,.13f,.32f,.34f,.06f);
                m.Box("metal",x,y,.19f,.18f,.14f,3.04f);
                m.Box("body",x,y,.19f,.23f,.25f,.57f);
                m.Box("accent",x,y,.64f,.24f,.26f,.06f);
                m.Box("body",x,y,.76f,.26f,.28f,.04f);
                for(var bolt=-1;bolt<=1;bolt+=2)
                    m.Cylinder("metal",x+bolt*.12f,y,.192f,.025f,.009f,0xBBBBBBFF,8);
            }
        }
        if(includeCanopy)
        {
        // Low, flat canopy with a rounded fascia and continuous colored perimeter.
        m.Slab("body",4.76f,7.36f,.20f,3.23f,.16f,.03f);
        m.RoundedStrip("accent",4.765f,7.365f,.20f,3.265f,.035f,.025f);
        m.Slab("metal",4.35f,6.95f,.12f,3.212f,.018f,0,0,0,0xBBBBBBFF);
        for(var panel=-2;panel<=2;panel++)
        {
            m.Box("deck",0,panel*1.30f,3.39f,4.10f,1.24f,.018f);
            for(var line=-4;line<=4;line++) m.Box("body",line*.42f,panel*1.30f,3.409f,.012f,1.24f,.002f);
        }
        for(var side=-1;side<=1;side+=2)
            m.Box("accent",side*1.77f,0,3.199f,.045f,5.7f,.015f);
        }
        return m.Finish();
    }

    private static PropModel WallShell()
    {
        var m=new Mesh();
        // Opaque sides and ends close the bay below the independent roof. A little
        // overlap into the roof/deck prevents daylight seams during animation.
        for(var side=-1;side<=1;side+=2)
        {
            m.Box("body",side*2.255f,0,.12f,.10f,6.95f,3.15f);
            m.Box("body",0,side*3.425f,.12f,4.51f,.10f,3.15f);
            m.Box("accent",side*2.31f,0,.22f,.014f,6.78f,.022f);
            m.Box("accent",0,side*3.48f,.22f,4.44f,.014f,.022f);
            // Narrow service seams and low horizontal vent details.
            for(var panel=-2;panel<=2;panel++)
                m.Box("metal",side*2.31f,panel*1.28f,.40f,.009f,.012f,2.58f,0x333333FF);
            for(var vent=0;vent<5;vent++)
                m.Box("metal",0,side*3.482f,.47f+vent*.055f,1.1f,.006f,.012f,0x333333FF);
        }
        return m.Finish();
    }

    private static PropModel Tablet()
    {
        var m=new Mesh();
        m.Slab("body",.56f,.46f,.08f,0,.065f,.018f);
        m.Slab("metal",.49f,.39f,.065f,.066f,.013f,0,0,0,0x777777FF);
        m.Box("body",0,.035f,.079f,.115f,.13f,1.02f);
        m.Box("metal",0,.11f,.12f,.055f,.012f,.85f,0x808080FF);
        // Back shell and distinct bezel surround an unobstructed 2:3 screen plane.
        m.Box("body",0,.0f,.89f,.64f,.14f,1.00f);
        m.Box("body",-.31f,-.079f,.90f,.06f,.04f,.98f);
        m.Box("body",.31f,-.079f,.90f,.06f,.04f,.98f);
        m.Box("body",0,-.079f,1.81f,.56f,.04f,.07f);
        m.Box("body",0,-.079f,.90f,.56f,.04f,.07f);
        m.Screen(0,-.081f,1.39f,.56f,.84f);
        m.Box("accent",0,-.101f,.931f,.27f,.005f,.006f);
        m.Box("accent",-.323f,.021f,1.03f,.008f,.065f,.66f);
        m.Box("accent",.323f,.021f,1.03f,.008f,.065f,.66f);
        for(var i=0;i<7;i++) m.Box("metal",(i-3)*.045f,.073f,1.10f,.021f,.006f,.05f,0x777777FF);
        return m.Finish();
    }

    private static PropModel Booth()
    {
        var m=new Mesh();
        m.Slab("body",1.85f,.70f,.055f,0,.10f,.025f);
        m.Box("body",0,.225f,.10f,1.75f,.20f,2.04f);
        m.Box("body",-.825f,-.045f,.10f,.10f,.54f,2.04f);
        m.Box("body",.825f,-.045f,.10f,.10f,.54f,2.04f);
        m.Box("body",0,-.045f,1.965f,1.75f,.54f,.18f);
        m.Box("body",0,-.045f,.10f,1.75f,.54f,.22f);
        m.Box("body",.38f,-.045f,.32f,.10f,.54f,1.645f);
        // Three shelves, with two independent capsule forms per shelf.
        for(var row=0;row<3;row++)
        {
            var h=.54f+row*.45f;
            m.Box("metal",-.24f,-.01f,h-.15f,1.14f,.44f,.022f,0xAAAAAAFF);
            m.Box("accent",-.24f,-.237f,h-.15f,1.11f,.01f,.009f);
            for(var column=0;column<2;column++) m.Capsule(-.53f+column*.54f,-.075f,h);
        }
        m.Box("glass",-.24f,-.274f,.36f,1.11f,.008f,1.56f,0xFFFFFFFF);
        m.Box("body",.645f,-.294f,.975f,.49f,.053f,.75f);
        m.Screen(.645f,-.326f,1.35f,.42f,.63f);
        m.Box("accent",.645f,-.326f,.996f,.27f,.004f,.009f);
        m.Box("accent",-.876f,-.304f,.24f,.007f,.023f,1.80f);
        m.Box("accent",.876f,-.304f,.24f,.007f,.023f,1.80f);
        m.Box("accent",0,-.318f,2.03f,1.63f,.008f,.014f);
        // Lower service hatch, handle and ventilation slots.
        m.Box("metal",.645f,-.318f,.43f,.32f,.008f,.34f,0x888888FF);
        for(var i=0;i<5;i++) m.Box("body",.645f,-.326f,.46f+i*.052f,.25f,.004f,.011f);
        return m.Finish();
    }

    private static YtdFile BuildTextures(string output)
    {
        var textures=new List<(string Name,byte[]? Image)>();
        var folder=Path.Combine(output,"textures");Directory.CreateDirectory(folder);
        foreach(var (material,name) in TextureNames)
        {
            var rgb = material switch {
                "body" => (R:31,G:34,B:38), "deck"=>(R:48,G:51,B:55), "metal"=>(R:125,G:132,B:138),
                "screen"=>(R:6,G:10,B:13), "glass"=>(R:145,G:175,B:185), _=>(R:245,G:248,B:249) };
            using var image=new MagickImage(new MagickColor((byte)rgb.R,(byte)rgb.G,(byte)rgb.B,(byte)(material=="glass" ? 38:255)),256,256);
            if(material is "deck" or "body" or "metal")
            {
                using var pixels=image.GetPixels();
                var random=new Random(8117);
                for(var y=0;y<256;y++)for(var x=0;x<256;x++)
                {
                    var variation=random.Next(-3,4);
                    if(material=="deck" && ((x+y)%32<3 || (x-y+256)%32<3)) variation+=9;
                    if(material=="metal") variation+=(y%3==0 ? 4:0);
                    pixels.SetPixel(x,y,new byte[]{(byte)Math.Clamp(rgb.R+variation,0,255),(byte)Math.Clamp(rgb.G+variation,0,255),(byte)Math.Clamp(rgb.B+variation,0,255),255});
                }
            }
            image.Format=MagickFormat.Png;
            var png=image.ToByteArray();File.WriteAllBytes(Path.Combine(folder,name+".png"),png);
            textures.Add((name,png));
        }
        var result=new YtdFile();result.Load(YtdBuilder.Build(DictionaryName,textures));
        var reference=new YtdFile();reference.Load(File.ReadAllBytes(Path.Combine(ReferenceRoot,"stream/glowglyphs_txd_v4.ytd")));
        var palette=reference.TextureDict.Textures.data_items.Single(t=>t.Usage==TextureUsage.TINTPALETTE);
        if(palette.Width!=256 || palette.Height!=16) throw new InvalidDataException("Reference tint palette must be 256x16.");
        palette.Name=PaletteName;palette.NameHash=JenkHash.GenHash(PaletteName);
        var all=result.TextureDict.Textures.data_items.ToList();all.Add(palette);
        result.TextureDict.BuildFromTextureList(all);
        return result;
    }

    private static byte[] BuildDrawable(string name,PropModel model,string output)
    {
        var original=new YdrFile();
        original.Load(DrawableBuilder.BuildYdr(model,name,model.Geometries.Select(g=>TextureNames[g.MaterialName]).ToArray(),120f));
        var doc=new XmlDocument();doc.LoadXml(YdrXml.GetXml(original));
        doc.SelectSingleNode("/Drawable/Name")!.InnerText=name+".#dr";
        if(IsMovingPart(name))
        {
            var bounds=doc.SelectSingleNode("/Drawable/Bounds");
            if(bounds!=null)bounds.ParentNode!.RemoveChild(bounds);
        }
        var shaders=doc.SelectNodes("/Drawable/ShaderGroup/Shaders/Item")!.Cast<XmlNode>().ToArray();
        for(var i=0;i<model.Geometries.Count;i++)
        {
            var screen=model.Geometries[i].MaterialName=="screen";
            if(model.Geometries[i].MaterialName!="accent" && !screen) continue;
            // Reuse the exact PropBuilder shader generator that produced glowglyphs.
            var builder=new StringBuilder();
            typeof(DrawableBuilder).GetMethod("EmitEmissiveTintShader",BindingFlags.NonPublic|BindingFlags.Static)!
                .Invoke(null,new object[]{builder,TextureNames[screen ? "screen":"accent"],PaletteName,screen ? 1.0f:3.0f});
            var fragment=doc.CreateDocumentFragment();fragment.InnerXml=builder.ToString();
            if(screen)
            {
                // Un-tinted emissive surface keeps the replacement DUI legible at night.
                fragment.SelectSingleNode("Item/Name")!.InnerText="emissive";
                fragment.SelectSingleNode("Item/FileName")!.InnerText="emissive.sps";
                foreach(XmlNode parameter in fragment.SelectNodes("Item/Parameters/Item[@name='TintPaletteSampler' or @name='tintPaletteSelector']")!)
                    parameter.ParentNode!.RemoveChild(parameter);
            }
            shaders[i]!.ParentNode!.ReplaceChild(fragment,shaders[i]!);
        }
        // Skeleton-owned composite/BVH is preserved, including driveable deck ramps.
        var result=XmlYdr.GetYdr(doc).Save();
        doc.Save(Path.Combine(output,"xml",name+".ydr.xml"));
        return result;
    }

    private static object Validate(string name,PropModel expected,byte[] bytes,byte[] archetypeBytes,YtdFile textures,string output)
    {
        var ydr=new YdrFile();ydr.Load(bytes);
        var d=ydr.Drawable??throw new InvalidDataException(name+": no drawable");
        var moving=IsMovingPart(name);
        if(moving)
        {
            if(d.Bound!=null)throw new InvalidDataException(name+": animated shell/canopy must be collisionless");
        }
        else
        {
            if(d.Bound is not BoundComposite composite || composite.Children?.data_items?.Length<1)
                throw new InvalidDataException(name+": missing embedded composite collision");
            if(composite.Children!.data_items.Any(c=>c is not BoundBVH)) throw new InvalidDataException(name+": collision is not BVH");
        }
        if(d.Skeleton?.Bones?.Items?.Length != 1) throw new InvalidDataException(name+": skeleton must have one root bone");
        var shaderNames=new List<string>();
        var textureSet=textures.TextureDict.Textures.data_items.Select(t=>t.Name).ToHashSet();
        var tintCount=0;var triangles=0;var vertices=0;var screenVertices=0;
        foreach(var geometry in d.DrawableModels.High.SelectMany(m=>m.Geometries))
        {
            if(geometry.VerticesCount==0 || geometry.IndicesCount==0 || geometry.VerticesCount>65535)
                throw new InvalidDataException(name+": invalid geometry counts");
            if(geometry.ShaderID >= d.ShaderGroup.Shaders.data_items.Length) throw new InvalidDataException(name+": invalid shader index");
            triangles+=(int)geometry.TrianglesCount;vertices+=(int)geometry.VerticesCount;
            var shader=d.ShaderGroup.Shaders.data_items[geometry.ShaderID];
            if(shader.ParametersList.Parameters.Any(p=>p.Data is TextureBase t && t.Name==TextureNames["screen"]))
            {
                var corners=new HashSet<string>();
                for(var v=0;v<geometry.VerticesCount;v++)
                {
                    var uv=geometry.VertexData.GetVector2(v,6);
                    if(uv.X<0 || uv.X>1 || uv.Y<0 || uv.Y>1)throw new InvalidDataException(name+": screen UV outside 0..1");
                    corners.Add($"{uv.X},{uv.Y}");screenVertices++;
                }
                if(corners.Count!=4 || !corners.Contains("0,0") || !corners.Contains("1,1"))throw new InvalidDataException(name+": screen is missing full-frame UV corners");
            }
        }
        foreach(var shader in d.ShaderGroup.Shaders.data_items)
        {
            shaderNames.Add(shader.Name.ToString());
            foreach(var parameter in shader.ParametersList.Parameters)
                if(parameter.Data is TextureBase texture)
                {
                    if(!textureSet.Contains(texture.Name)) throw new InvalidDataException(name+": missing sampler "+texture.Name);
                    if(texture.Name==PaletteName)tintCount++;
                }
        }
        if(tintCount<1)throw new InvalidDataException(name+": no runtime tint palette binding");
        var ytyp=new YtypFile();ytyp.Load(archetypeBytes);
        if(ytyp.AllArchetypes.Length!=1)throw new InvalidDataException(name+": wrong archetype count");
        var xml=new XmlDocument();xml.LoadXml(MetaXml.GetXml(ytyp,out _));
        File.WriteAllText(Path.Combine(output,"xml",name+".ytyp.xml"),xml.OuterXml);
        var arch=ytyp.AllArchetypes[0];
        if(arch.Hash!=JenkHash.GenHash(name))throw new InvalidDataException(name+": archetype name mismatch");
        if(arch.BaseArchetypeDef.assetName.Hash!=JenkHash.GenHash(name) || arch.BaseArchetypeDef.physicsDictionary.Hash!=(moving ? 0:JenkHash.GenHash(name))
            || arch.BaseArchetypeDef.textureDictionary.Hash!=JenkHash.GenHash(DictionaryName))
            throw new InvalidDataException(name+": asset/physics/texture dictionary link mismatch");
        var serializedAgain=ydr.Save();var roundTrip=new YdrFile();roundTrip.Load(serializedAgain);
        if((roundTrip.Drawable.Bound==null)!=moving)throw new InvalidDataException(name+": collision policy changed on round trip");
        var reloadedTxd=new YtdFile();reloadedTxd.Load(textures.Save());
        if(reloadedTxd.TextureDict.Textures.data_items.Length!=8)throw new InvalidDataException("Shared YTD texture count mismatch");
        var palette=reloadedTxd.TextureDict.Textures.data_items.Single(t=>t.Name==PaletteName);
        if(palette.Usage!=TextureUsage.TINTPALETTE || palette.Width!=256 || palette.Height!=16 || palette.Levels!=1)
            throw new InvalidDataException("Tint palette metadata mismatch");
        var min=new[]{d.BoundingBoxMin.X,d.BoundingBoxMin.Y,d.BoundingBoxMin.Z};
        var max=new[]{d.BoundingBoxMax.X,d.BoundingBoxMax.Y,d.BoundingBoxMax.Z};
        if(Math.Abs(min[0]-expected.BoxMin.X)>.001f || Math.Abs(max[2]-expected.BoxMax.Z)>.001f)
            throw new InvalidDataException(name+": mesh bounds changed on serialization");
        return new {name,vertices,triangles,boundsMin=min,boundsMax=max,
            collision=moving ? "none: moving visual part; physicsDictionary=0":"Composite > GeometryBVH, double-sided triangles, root-bone attached",
            shaders=shaderNames,tintSamplers=tintCount,screenVertices,screenTexture=screenVertices>0 ? TextureNames["screen"]:null,
            paletteFormat=palette.Format.ToString(),paletteLevels=palette.Levels,paletteUsageFlags=palette.UsageFlags.ToString(),
            ydrBytes=bytes.Length,ydrSha256=Hash(bytes),ytypBytes=archetypeBytes.Length,
            checks=new[]{"Gen8 binary parse","YDR serialize/reload","nonempty render geometries","valid shader indices",
                "all texture samplers resolve","tint palette binding","collision policy checked","single root skeleton","archetype hash",
                "YTYP asset/physics/texture links","screen UV 0..1","YTD reload"} };
    }

    private static void SaveObj(PropModel model,string path)
    {
        var output=new StringBuilder("# Authored capsule prop source, GTA Z-up, metres\n");var offset=1;
        foreach(var group in model.Geometries)
        {
            output.AppendLine("g "+group.MaterialName);
            foreach(var v in group.Vertices)output.AppendLine($"v {v.Position.X} {v.Position.Y} {v.Position.Z}");
            for(var i=0;i<group.Indices.Count;i+=3)output.AppendLine($"f {group.Indices[i]+offset} {group.Indices[i+1]+offset} {group.Indices[i+2]+offset}");
            offset+=group.Vertices.Count;
        }
        File.WriteAllText(path,output.ToString());
    }
    private static string Hash(byte[] bytes)=>Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    private static void RenderPreview(PropModel model,string path)
    {
        const int width=1200,height=1000;
        using var image=new MagickImage(new MagickColor("#20242b"),width,height);
        var centre=model.Center;
        var look=System.Numerics.Vector3.Normalize(new System.Numerics.Vector3(-7,11,-6));
        var right=System.Numerics.Vector3.Normalize(System.Numerics.Vector3.Cross(look,System.Numerics.Vector3.UnitZ));
        var up=System.Numerics.Vector3.Cross(right,look);
        var scale=430f/model.Radius;
        var pixels=image.GetPixels();
        var depthBuffer=Enumerable.Repeat(float.PositiveInfinity,width*height).ToArray();
        var colors=new byte[width*height*4];
        for(var index=0;index<width*height;index++){colors[index*4]=32;colors[index*4+1]=36;colors[index*4+2]=43;colors[index*4+3]=255;}
        foreach(var geom in model.Geometries.OrderBy(g=>g.MaterialName=="glass" ? 1:0))
        for(var i=0;i<geom.Indices.Count;i+=3)
        {
            var a=geom.Vertices[geom.Indices[i]];var b=geom.Vertices[geom.Indices[i+1]];var c=geom.Vertices[geom.Indices[i+2]];
            if(System.Numerics.Vector3.Dot(a.Normal,look)>=0)continue;
            var shade=.65f+.35f*Math.Max(0,System.Numerics.Vector3.Dot(a.Normal,System.Numerics.Vector3.Normalize(new(-3,-4,8))));
            var rgb=geom.MaterialName switch {
                "accent"=>(R:24,G:255,B:176),"body"=>(R:40,G:44,B:50),"deck"=>(R:69,G:75,B:83),
                "metal"=>(R:145,G:155,B:166),"screen"=>(R:4,G:9,B:13),"glass"=>(R:112,G:152,B:165),_=>(R:232,G:236,B:240) };
            var points=new[]{a.Position,b.Position,c.Position};
            var projected=points.Select(v=>new PointD(width*.5+System.Numerics.Vector3.Dot(v-centre,right)*scale,
                height*.52-System.Numerics.Vector3.Dot(v-centre,up)*scale)).ToArray();
            var depths=points.Select(v=>System.Numerics.Vector3.Dot(v-centre,look)).ToArray();
            var alpha=geom.MaterialName=="glass"?.23f:1f;
            var minX=Math.Max(0,(int)Math.Floor(projected.Min(p=>p.X)));var maxX=Math.Min(width-1,(int)Math.Ceiling(projected.Max(p=>p.X)));
            var minY=Math.Max(0,(int)Math.Floor(projected.Min(p=>p.Y)));var maxY=Math.Min(height-1,(int)Math.Ceiling(projected.Max(p=>p.Y)));
            double Edge(PointD p,PointD q,double x,double y)=>(x-p.X)*(q.Y-p.Y)-(y-p.Y)*(q.X-p.X);
            var area=Edge(projected[0],projected[1],projected[2].X,projected[2].Y);
            if(Math.Abs(area)<.000001)continue;
            for(var y=minY;y<=maxY;y++)for(var x=minX;x<=maxX;x++)
            {
                var w0=Edge(projected[1],projected[2],x+.5,y+.5)/area;
                var w1=Edge(projected[2],projected[0],x+.5,y+.5)/area;
                var w2=1-w0-w1;
                if(w0<0||w1<0||w2<0)continue;
                var depth=(float)(w0*depths[0]+w1*depths[1]+w2*depths[2]);var index=y*width+x;
                if(depth>=depthBuffer[index])continue;
                colors[index*4]=(byte)(colors[index*4]*(1-alpha)+rgb.R*shade*alpha);
                colors[index*4+1]=(byte)(colors[index*4+1]*(1-alpha)+rgb.G*shade*alpha);
                colors[index*4+2]=(byte)(colors[index*4+2]*(1-alpha)+rgb.B*shade*alpha);
                if(alpha==1)depthBuffer[index]=depth;
            }
        }
        for(var y=0;y<height;y++)for(var x=0;x<width;x++)
        {
            var index=(y*width+x)*4;
            pixels.SetPixel(x,y,new[]{colors[index],colors[index+1],colors[index+2],(byte)255});
        }
        pixels.Dispose();
        image.Format=MagickFormat.Png;image.Write(path);
    }
}
