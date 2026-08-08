#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <new>
#include <unordered_map>
#include <utility>
#include <vector>

namespace {

struct Vec3 {
    float x, y, z;
};

struct Bounds {
    Vec3 min;
    Vec3 max;
};

struct Triangle {
    Vec3 a, b, c;
    Bounds bounds;
    Vec3 centroid;
};

struct Node {
    Bounds bounds;
    uint32_t first;
    uint32_t count;
    int32_t left;
    int32_t right;
};

static Vec3 add(Vec3 a, Vec3 b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
static Vec3 sub(Vec3 a, Vec3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
static Vec3 mul(Vec3 a, float b) { return {a.x * b, a.y * b, a.z * b}; }
static float dot(Vec3 a, Vec3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }

static Bounds empty_bounds() {
    const float limit = std::numeric_limits<float>::max();
    return {{limit, limit, limit}, {-limit, -limit, -limit}};
}

static void include(Bounds& bounds, Vec3 value) {
    bounds.min.x = std::min(bounds.min.x, value.x);
    bounds.min.y = std::min(bounds.min.y, value.y);
    bounds.min.z = std::min(bounds.min.z, value.z);
    bounds.max.x = std::max(bounds.max.x, value.x);
    bounds.max.y = std::max(bounds.max.y, value.y);
    bounds.max.z = std::max(bounds.max.z, value.z);
}

static void include(Bounds& bounds, Bounds value) {
    include(bounds, value.min);
    include(bounds, value.max);
}

static float point_bounds_distance_squared(Vec3 point, Bounds bounds) {
    const float dx = std::max(std::max(bounds.min.x - point.x, 0.0f), point.x - bounds.max.x);
    const float dy = std::max(std::max(bounds.min.y - point.y, 0.0f), point.y - bounds.max.y);
    const float dz = std::max(std::max(bounds.min.z - point.z, 0.0f), point.z - bounds.max.z);
    return dx * dx + dy * dy + dz * dz;
}

// Closest-point regions from Real-Time Collision Detection, Christer Ericson.
static float point_triangle_distance_squared(Vec3 p, const Triangle& triangle) {
    const Vec3 ab = sub(triangle.b, triangle.a);
    const Vec3 ac = sub(triangle.c, triangle.a);
    const Vec3 ap = sub(p, triangle.a);
    const float d1 = dot(ab, ap);
    const float d2 = dot(ac, ap);
    if (d1 <= 0.0f && d2 <= 0.0f) return dot(ap, ap);

    const Vec3 bp = sub(p, triangle.b);
    const float d3 = dot(ab, bp);
    const float d4 = dot(ac, bp);
    if (d3 >= 0.0f && d4 <= d3) return dot(bp, bp);

    const float vc = d1 * d4 - d3 * d2;
    if (vc <= 0.0f && d1 >= 0.0f && d3 <= 0.0f) {
        const Vec3 projection = add(triangle.a, mul(ab, d1 / (d1 - d3)));
        const Vec3 delta = sub(p, projection);
        return dot(delta, delta);
    }

    const Vec3 cp = sub(p, triangle.c);
    const float d5 = dot(ab, cp);
    const float d6 = dot(ac, cp);
    if (d6 >= 0.0f && d5 <= d6) return dot(cp, cp);

    const float vb = d5 * d2 - d1 * d6;
    if (vb <= 0.0f && d2 >= 0.0f && d6 <= 0.0f) {
        const Vec3 projection = add(triangle.a, mul(ac, d2 / (d2 - d6)));
        const Vec3 delta = sub(p, projection);
        return dot(delta, delta);
    }

    const float va = d3 * d6 - d5 * d4;
    if (va <= 0.0f && (d4 - d3) >= 0.0f && (d5 - d6) >= 0.0f) {
        const Vec3 edge = sub(triangle.c, triangle.b);
        const Vec3 projection = add(triangle.b, mul(edge, (d4 - d3) / ((d4 - d3) + (d5 - d6))));
        const Vec3 delta = sub(p, projection);
        return dot(delta, delta);
    }

    const float denominator = 1.0f / (va + vb + vc);
    const Vec3 projection = add(triangle.a, add(mul(ab, vb * denominator), mul(ac, vc * denominator)));
    const Vec3 delta = sub(p, projection);
    return dot(delta, delta);
}

class TriangleBvh {
public:
    explicit TriangleBvh(std::vector<Triangle> triangles) : triangles_(std::move(triangles)) {
        order_.resize(triangles_.size());
        for (uint32_t index = 0; index < order_.size(); ++index) order_[index] = index;
        build(0, static_cast<uint32_t>(order_.size()));
    }

    float distance_squared(Vec3 point) const {
        float best = std::numeric_limits<float>::max();
        nearest(0, point, best);
        return best;
    }

    uint32_t ray_intersections(Vec3 origin) const {
        // A non-axis-aligned direction avoids coherent edge/vertex degeneracies.
        const Vec3 direction = {1.0f, 0.000137f, 0.000263f};
        return ray_count(0, origin, direction);
    }

private:
    int32_t build(uint32_t first, uint32_t count) {
        Node node = {empty_bounds(), first, count, -1, -1};
        Bounds centroids = empty_bounds();
        for (uint32_t index = first; index < first + count; ++index) {
            include(node.bounds, triangles_[order_[index]].bounds);
            include(centroids, triangles_[order_[index]].centroid);
        }
        const int32_t node_index = static_cast<int32_t>(nodes_.size());
        nodes_.push_back(node);
        if (count <= 8) return node_index;

        const Vec3 extent = sub(centroids.max, centroids.min);
        int axis = 0;
        if (extent.y > extent.x) axis = 1;
        if ((axis == 0 ? extent.x : extent.y) < extent.z) axis = 2;
        const uint32_t middle = first + count / 2;
        std::nth_element(order_.begin() + first, order_.begin() + middle, order_.begin() + first + count,
            [&](uint32_t left, uint32_t right) {
                const Vec3 a = triangles_[left].centroid;
                const Vec3 b = triangles_[right].centroid;
                return axis == 0 ? a.x < b.x : (axis == 1 ? a.y < b.y : a.z < b.z);
            });
        nodes_[node_index].count = 0;
        nodes_[node_index].left = build(first, middle - first);
        nodes_[node_index].right = build(middle, first + count - middle);
        return node_index;
    }

    void nearest(int32_t node_index, Vec3 point, float& best) const {
        const Node& node = nodes_[node_index];
        if (point_bounds_distance_squared(point, node.bounds) >= best) return;
        if (node.count > 0) {
            for (uint32_t index = node.first; index < node.first + node.count; ++index)
                best = std::min(best, point_triangle_distance_squared(point, triangles_[order_[index]]));
            return;
        }
        const Node& left = nodes_[node.left];
        const Node& right = nodes_[node.right];
        const float left_distance = point_bounds_distance_squared(point, left.bounds);
        const float right_distance = point_bounds_distance_squared(point, right.bounds);
        if (left_distance < right_distance) {
            nearest(node.left, point, best);
            nearest(node.right, point, best);
        } else {
            nearest(node.right, point, best);
            nearest(node.left, point, best);
        }
    }

    static bool ray_bounds(Vec3 origin, Vec3 direction, Bounds bounds) {
        float minimum = 0.0f;
        float maximum = std::numeric_limits<float>::max();
        const float origins[3] = {origin.x, origin.y, origin.z};
        const float directions[3] = {direction.x, direction.y, direction.z};
        const float lower[3] = {bounds.min.x, bounds.min.y, bounds.min.z};
        const float upper[3] = {bounds.max.x, bounds.max.y, bounds.max.z};
        for (int axis = 0; axis < 3; ++axis) {
            const float inverse = 1.0f / directions[axis];
            float near_value = (lower[axis] - origins[axis]) * inverse;
            float far_value = (upper[axis] - origins[axis]) * inverse;
            if (near_value > far_value) std::swap(near_value, far_value);
            minimum = std::max(minimum, near_value);
            maximum = std::min(maximum, far_value);
            if (minimum > maximum) return false;
        }
        return true;
    }

    static bool ray_triangle(Vec3 origin, Vec3 direction, const Triangle& triangle) {
        const Vec3 edge1 = sub(triangle.b, triangle.a);
        const Vec3 edge2 = sub(triangle.c, triangle.a);
        const Vec3 p = {direction.y * edge2.z - direction.z * edge2.y,
                        direction.z * edge2.x - direction.x * edge2.z,
                        direction.x * edge2.y - direction.y * edge2.x};
        const float determinant = dot(edge1, p);
        if (std::fabs(determinant) < 1.0e-8f) return false;
        const float inverse = 1.0f / determinant;
        const Vec3 t = sub(origin, triangle.a);
        const float u = dot(t, p) * inverse;
        if (u < 0.0f || u > 1.0f) return false;
        const Vec3 q = {t.y * edge1.z - t.z * edge1.y,
                        t.z * edge1.x - t.x * edge1.z,
                        t.x * edge1.y - t.y * edge1.x};
        const float v = dot(direction, q) * inverse;
        if (v < 0.0f || u + v > 1.0f) return false;
        return dot(edge2, q) * inverse > 1.0e-6f;
    }

    uint32_t ray_count(int32_t node_index, Vec3 origin, Vec3 direction) const {
        const Node& node = nodes_[node_index];
        if (!ray_bounds(origin, direction, node.bounds)) return 0;
        if (node.count > 0) {
            uint32_t result = 0;
            for (uint32_t index = node.first; index < node.first + node.count; ++index)
                result += ray_triangle(origin, direction, triangles_[order_[index]]) ? 1u : 0u;
            return result;
        }
        return ray_count(node.left, origin, direction) + ray_count(node.right, origin, direction);
    }

    std::vector<Triangle> triangles_;
    std::vector<uint32_t> order_;
    std::vector<Node> nodes_;
};

static uint64_t edge_key(uint32_t a, uint32_t b) {
    if (a > b) std::swap(a, b);
    return (static_cast<uint64_t>(a) << 32u) | b;
}

static bool is_watertight(const uint32_t* indices, size_t index_count) {
    std::unordered_map<uint64_t, uint32_t> edges;
    edges.reserve(index_count);
    for (size_t index = 0; index < index_count; index += 3) {
        ++edges[edge_key(indices[index], indices[index + 1])];
        ++edges[edge_key(indices[index + 1], indices[index + 2])];
        ++edges[edge_key(indices[index + 2], indices[index])];
    }
    for (const auto& edge : edges)
        if (edge.second != 2) return false;
    return true;
}

} // namespace

extern "C" {

struct ScrapbotDistanceFieldResult {
    float* samples;
    uint32_t sample_count;
    uint32_t dimensions[3];
    float bounds_min[3];
    float bounds_max[3];
    float voxel_size;
    uint32_t signed_field;
};

ScrapbotDistanceFieldResult scrapbot_distance_field_build(
    const float* positions,
    size_t vertex_count,
    size_t vertex_stride,
    const uint32_t* indices,
    size_t index_count,
    uint32_t longest_axis_cells,
    uint32_t padding_cells) {
    ScrapbotDistanceFieldResult result = {};
    if (!positions || !indices || vertex_count == 0 || index_count < 3 || index_count % 3 != 0 ||
        vertex_stride < sizeof(float) * 3 || longest_axis_cells < 4 || longest_axis_cells > 256 ||
        padding_cells > longest_axis_cells / 2) return result;

    auto position = [&](uint32_t index) {
        const uint8_t* bytes = reinterpret_cast<const uint8_t*>(positions) + size_t(index) * vertex_stride;
        const float* value = reinterpret_cast<const float*>(bytes);
        return Vec3{value[0], value[1], value[2]};
    };
    Bounds source_bounds = empty_bounds();
    std::vector<Triangle> triangles;
    triangles.reserve(index_count / 3);
    for (size_t index = 0; index < index_count; index += 3) {
        if (indices[index] >= vertex_count || indices[index + 1] >= vertex_count || indices[index + 2] >= vertex_count)
            return result;
        Triangle triangle = {};
        triangle.a = position(indices[index]);
        triangle.b = position(indices[index + 1]);
        triangle.c = position(indices[index + 2]);
        triangle.bounds = empty_bounds();
        include(triangle.bounds, triangle.a);
        include(triangle.bounds, triangle.b);
        include(triangle.bounds, triangle.c);
        triangle.centroid = mul(add(add(triangle.a, triangle.b), triangle.c), 1.0f / 3.0f);
        include(source_bounds, triangle.bounds);
        triangles.push_back(triangle);
    }
    const Vec3 extent = sub(source_bounds.max, source_bounds.min);
    const float longest = std::max(extent.x, std::max(extent.y, extent.z));
    if (!(longest > 0.0f) || !std::isfinite(longest)) return result;
    const float voxel_size = longest / float(longest_axis_cells);
    const Vec3 padding = {voxel_size * padding_cells, voxel_size * padding_cells, voxel_size * padding_cells};
    const Vec3 field_min = sub(source_bounds.min, padding);
    const Vec3 field_max = add(source_bounds.max, padding);
    const Vec3 field_extent = sub(field_max, field_min);
    const uint32_t dimensions[3] = {
        std::max(1u, uint32_t(std::ceil(field_extent.x / voxel_size))),
        std::max(1u, uint32_t(std::ceil(field_extent.y / voxel_size))),
        std::max(1u, uint32_t(std::ceil(field_extent.z / voxel_size))),
    };
    const uint64_t sample_count = uint64_t(dimensions[0]) * dimensions[1] * dimensions[2];
    if (sample_count == 0 || sample_count > 256ull * 256ull * 256ull) return result;

    TriangleBvh bvh(std::move(triangles));
    float* samples = new (std::nothrow) float[sample_count];
    if (!samples) return result;
    const bool signed_field = is_watertight(indices, index_count);
    uint64_t cursor = 0;
    for (uint32_t z = 0; z < dimensions[2]; ++z) {
        for (uint32_t y = 0; y < dimensions[1]; ++y) {
            for (uint32_t x = 0; x < dimensions[0]; ++x) {
                const Vec3 point = {
                    field_min.x + (float(x) + 0.5f) * voxel_size,
                    field_min.y + (float(y) + 0.5f) * voxel_size,
                    field_min.z + (float(z) + 0.5f) * voxel_size,
                };
                float distance = std::sqrt(bvh.distance_squared(point));
                if (signed_field && (bvh.ray_intersections(point) & 1u)) distance = -distance;
                samples[cursor++] = distance;
            }
        }
    }
    result.samples = samples;
    result.sample_count = static_cast<uint32_t>(sample_count);
    for (int axis = 0; axis < 3; ++axis) result.dimensions[axis] = dimensions[axis];
    result.bounds_min[0] = field_min.x; result.bounds_min[1] = field_min.y; result.bounds_min[2] = field_min.z;
    result.bounds_max[0] = field_max.x; result.bounds_max[1] = field_max.y; result.bounds_max[2] = field_max.z;
    result.voxel_size = voxel_size;
    result.signed_field = signed_field ? 1u : 0u;
    return result;
}

void scrapbot_distance_field_free(ScrapbotDistanceFieldResult result) {
    delete[] result.samples;
}

} // extern "C"
