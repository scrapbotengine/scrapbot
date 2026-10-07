fn scrapbot_vertex(input: Scrapbot_Vertex) -> Scrapbot_Vertex {
    var output = input;
    output.position.y += sin(scrapbot_time_seconds() + input.position.x) * 0.15;
    return output;
}

fn scrapbot_fragment(input: Scrapbot_Fragment) -> Scrapbot_Surface {
    return Scrapbot_Surface(input.base_color, input.world_normal, 0.5, vec3<f32>(0.0), 0.0);
}
