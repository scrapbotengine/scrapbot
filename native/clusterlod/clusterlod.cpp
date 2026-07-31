#define CLUSTERLOD_IMPLEMENTATION
#include "../../third_party/meshoptimizer/src/meshoptimizer.h"
#include "../../third_party/meshoptimizer/demo/clusterlod.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <vector>

extern "C"
{
struct scrapbot_clod_group
{
	float bounds[4];
	float error;
	uint32_t depth;
	uint32_t cluster_offset;
	uint32_t cluster_count;
};

struct scrapbot_clod_cluster
{
	uint32_t vertex_offset;
	uint32_t triangle_offset;
	uint32_t vertex_count;
	uint32_t triangle_count;
	float bounds[4];
	float cone_axis_cutoff[4];
	int32_t group;
	int32_t refined_group;
};

struct scrapbot_clod_result
{
	scrapbot_clod_group* groups;
	scrapbot_clod_cluster* clusters;
	uint32_t* vertices;
	uint8_t* triangles;
	size_t group_count;
	size_t cluster_count;
	size_t vertex_count;
	size_t triangle_byte_count;
	uint32_t max_depth;
};
}

static_assert(sizeof(scrapbot_clod_group) == 32, "cluster group ABI changed");
static_assert(sizeof(scrapbot_clod_cluster) == 56, "cluster ABI changed");

namespace
{
struct scrapbot_clod_output
{
	const float* positions;
	size_t vertex_count;
	size_t vertex_stride;
	std::vector<scrapbot_clod_group> groups;
	std::vector<scrapbot_clod_cluster> clusters;
	std::vector<uint32_t> vertices;
	std::vector<uint8_t> triangles;
};

static int scrapbot_clod_emit(void* context, clodGroup group, const clodCluster* clusters, size_t cluster_count)
{
	scrapbot_clod_output& output = *static_cast<scrapbot_clod_output*>(context);
	const int group_index = int(output.groups.size());

	scrapbot_clod_group emitted_group = {};
	emitted_group.bounds[0] = group.simplified.center[0];
	emitted_group.bounds[1] = group.simplified.center[1];
	emitted_group.bounds[2] = group.simplified.center[2];
	emitted_group.bounds[3] = group.simplified.radius;
	emitted_group.error = group.simplified.error;
	emitted_group.depth = uint32_t(group.depth);
	emitted_group.cluster_offset = uint32_t(output.clusters.size());
	emitted_group.cluster_count = uint32_t(cluster_count);
	output.groups.push_back(emitted_group);

	for (size_t index = 0; index < cluster_count; ++index)
	{
		const clodCluster& cluster = clusters[index];
		const size_t vertex_offset = output.vertices.size();
		const size_t triangle_offset = output.triangles.size();
		output.vertices.resize(vertex_offset + cluster.vertex_count);
		output.triangles.resize(triangle_offset + cluster.index_count);
		const size_t vertex_count = clodLocalIndices(
		    &output.vertices[vertex_offset],
		    &output.triangles[triangle_offset],
		    cluster.indices,
		    cluster.index_count);

		meshopt_Bounds bounds = meshopt_computeMeshletBounds(
		    &output.vertices[vertex_offset],
		    &output.triangles[triangle_offset],
		    cluster.index_count / 3,
		    output.positions,
		    output.vertex_count,
		    output.vertex_stride);

		scrapbot_clod_cluster emitted = {};
		emitted.vertex_offset = uint32_t(vertex_offset);
		emitted.triangle_offset = uint32_t(triangle_offset);
		emitted.vertex_count = uint32_t(vertex_count);
		emitted.triangle_count = uint32_t(cluster.index_count / 3);
		emitted.bounds[0] = bounds.center[0];
		emitted.bounds[1] = bounds.center[1];
		emitted.bounds[2] = bounds.center[2];
		emitted.bounds[3] = bounds.radius;
		emitted.cone_axis_cutoff[0] = bounds.cone_axis[0];
		emitted.cone_axis_cutoff[1] = bounds.cone_axis[1];
		emitted.cone_axis_cutoff[2] = bounds.cone_axis[2];
		emitted.cone_axis_cutoff[3] = bounds.cone_cutoff;
		emitted.group = group_index;
		emitted.refined_group = cluster.refined;
		output.clusters.push_back(emitted);
	}

	return group_index;
}

template <typename T>
static T* scrapbot_clod_copy(const std::vector<T>& source)
{
	if (source.empty())
		return NULL;
	T* result = static_cast<T*>(malloc(source.size() * sizeof(T)));
	if (result)
		memcpy(result, source.data(), source.size() * sizeof(T));
	return result;
}
}

extern "C" scrapbot_clod_result scrapbot_clod_build(
    const uint32_t* indices,
    size_t index_count,
    const float* vertices,
    size_t vertex_count,
    size_t vertex_stride)
{
	scrapbot_clod_result result = {};
	if (!indices || index_count == 0 || !vertices || vertex_count == 0)
		return result;

	const float attribute_weights[] = {0.5f, 0.5f, 0.5f, 1.f, 1.f};
	clodMesh mesh = {};
	mesh.indices = indices;
	mesh.index_count = index_count;
	mesh.vertex_count = vertex_count;
	mesh.vertex_positions = vertices;
	mesh.vertex_positions_stride = vertex_stride;
	mesh.vertex_attributes = vertices + 3;
	mesh.vertex_attributes_stride = vertex_stride;
	mesh.attribute_weights = attribute_weights;
	mesh.attribute_count = sizeof(attribute_weights) / sizeof(attribute_weights[0]);
	mesh.attribute_protect_mask = (1u << 3) | (1u << 4);

	scrapbot_clod_output output = {};
	output.positions = vertices;
	output.vertex_count = vertex_count;
	output.vertex_stride = vertex_stride;
	clodConfig config = clodDefaultConfig(124);
	config.max_vertices = 64;
	config.optimize_bounds = true;
	clodBuild(config, mesh, &output, &scrapbot_clod_emit);

	if (output.groups.empty() || output.clusters.empty())
		return result;

	result.groups = scrapbot_clod_copy(output.groups);
	result.clusters = scrapbot_clod_copy(output.clusters);
	result.vertices = scrapbot_clod_copy(output.vertices);
	result.triangles = scrapbot_clod_copy(output.triangles);
	if (!result.groups || !result.clusters || !result.vertices || !result.triangles)
	{
		free(result.groups);
		free(result.clusters);
		free(result.vertices);
		free(result.triangles);
		return scrapbot_clod_result();
	}

	result.group_count = output.groups.size();
	result.cluster_count = output.clusters.size();
	result.vertex_count = output.vertices.size();
	result.triangle_byte_count = output.triangles.size();
	for (size_t index = 0; index < output.groups.size(); ++index)
		result.max_depth = output.groups[index].depth > result.max_depth ? output.groups[index].depth : result.max_depth;
	return result;
}

extern "C" void scrapbot_clod_free(scrapbot_clod_result result)
{
	free(result.groups);
	free(result.clusters);
	free(result.vertices);
	free(result.triangles);
}
