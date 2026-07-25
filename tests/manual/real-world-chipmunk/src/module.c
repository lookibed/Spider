#include <stdint.h>

#include "chipmunk/chipmunk.h"

void shim_reset_heap(void);

typedef struct Scene {
    cpSpace *space;
    cpBody *bodies[4];
} Scene;

static uint32_t rotl32(uint32_t value, uint32_t shift) {
    return (value << shift) | (value >> (32U - shift));
}

static uint32_t fold_u32(uint32_t hash, uint32_t value) {
    hash ^= value + 0x9E3779B9U + (hash << 6U) + (hash >> 2U);
    return rotl32(hash, 7U);
}

static uint32_t hash_cpfloat(cpFloat value) {
    union {
        double f64;
        uint64_t u64;
    } bits;

    bits.f64 = (double)value;
    return (uint32_t)(bits.u64 ^ (bits.u64 >> 32U));
}

static void add_box(Scene *scene, int index, cpFloat mass, cpFloat width, cpFloat height, cpVect position) {
    cpFloat moment = cpMomentForBox(mass, width, height);
    cpBody *body = cpBodyNew(mass, moment);
    cpShape *shape = cpBoxShapeNew(body, width, height, 0.0);

    cpBodySetPosition(body, position);
    cpShapeSetFriction(shape, 0.85);
    cpShapeSetElasticity(shape, 0.05);

    cpSpaceAddBody(scene->space, body);
    cpSpaceAddShape(scene->space, shape);
    scene->bodies[index] = body;
}

static void add_circle(Scene *scene, int index, cpFloat mass, cpFloat radius, cpVect position) {
    cpFloat moment = cpMomentForCircle(mass, 0.0, radius, cpvzero);
    cpBody *body = cpBodyNew(mass, moment);
    cpShape *shape = cpCircleShapeNew(body, radius, cpvzero);

    cpBodySetPosition(body, position);
    cpShapeSetFriction(shape, 0.8);
    cpShapeSetElasticity(shape, 0.1);

    cpSpaceAddBody(scene->space, body);
    cpSpaceAddShape(scene->space, shape);
    scene->bodies[index] = body;
}

static Scene build_scene(int variant) {
    Scene scene;
    cpShape *ground = 0;
    cpShape *slope = 0;
    cpConstraint *pivot = 0;
    cpConstraint *spring = 0;
    cpConstraint *slide = 0;

    shim_reset_heap();

    scene.space = cpSpaceNew();
    scene.bodies[0] = 0;
    scene.bodies[1] = 0;
    scene.bodies[2] = 0;
    scene.bodies[3] = 0;

    cpSpaceSetIterations(scene.space, variant ? 24 : 20);
    cpSpaceSetGravity(scene.space, variant ? cpv(18.0, -135.0) : cpv(0.0, -120.0));
    cpSpaceSetDamping(scene.space, variant ? 0.993 : 0.997);
    cpSpaceSetSleepTimeThreshold(scene.space, INFINITY);
    cpSpaceSetCollisionSlop(scene.space, 0.05);

    ground = cpSegmentShapeNew(cpSpaceGetStaticBody(scene.space), cpv(-40.0, -12.0), cpv(40.0, -12.0), 0.0);
    cpShapeSetFriction(ground, 1.0);
    cpShapeSetElasticity(ground, 0.0);
    cpSpaceAddShape(scene.space, ground);

    slope = cpSegmentShapeNew(
        cpSpaceGetStaticBody(scene.space),
        variant ? cpv(-16.0, -2.0) : cpv(10.0, -8.0),
        variant ? cpv(16.0, 6.0) : cpv(28.0, -1.0),
        0.0
    );
    cpShapeSetFriction(slope, 0.9);
    cpShapeSetElasticity(slope, 0.0);
    cpSpaceAddShape(scene.space, slope);

    add_box(&scene, 0, 1.5, 2.4, 2.0, cpv(-8.0, 4.0));
    add_circle(&scene, 1, 1.0, 1.2, cpv(-2.5, 10.0));
    add_box(&scene, 2, 1.75, 2.0, 2.0, cpv(3.0, 15.0));
    add_circle(&scene, 3, 1.15, 1.0, cpv(8.0, 20.0));

    cpBodySetAngle(scene.bodies[0], 0.15);
    cpBodySetAngle(scene.bodies[2], -0.2);

    pivot = cpPivotJointNew(cpSpaceGetStaticBody(scene.space), scene.bodies[0], cpv(-8.0, 6.0));
    cpConstraintSetMaxForce(pivot, 8000.0);
    cpSpaceAddConstraint(scene.space, pivot);

    spring = cpDampedSpringNew(scene.bodies[1], scene.bodies[2], cpvzero, cpvzero, 6.5, 140.0, variant ? 5.0 : 4.0);
    cpConstraintSetMaxForce(spring, 12000.0);
    cpSpaceAddConstraint(scene.space, spring);

    slide = cpSlideJointNew(scene.bodies[2], scene.bodies[3], cpvzero, cpvzero, 2.5, variant ? 7.0 : 6.0);
    cpConstraintSetMaxForce(slide, 10000.0);
    cpSpaceAddConstraint(scene.space, slide);

    return scene;
}

static void step_scene(Scene *scene, int32_t iterations) {
    int32_t i = 0;
    for (i = 0; i < iterations; i++) {
        cpSpaceStep(scene->space, 1.0 / 120.0);
    }
}

static uint32_t scene_hash(Scene *scene) {
    uint32_t hash = 0x13579BDFU;
    int i = 0;

    for (i = 0; i < 4; i++) {
        cpVect position = cpBodyGetPosition(scene->bodies[i]);
        cpVect velocity = cpBodyGetVelocity(scene->bodies[i]);
        cpFloat angle = cpBodyGetAngle(scene->bodies[i]);
        cpFloat angular_velocity = cpBodyGetAngularVelocity(scene->bodies[i]);

        hash = fold_u32(hash, hash_cpfloat(position.x));
        hash = fold_u32(hash, hash_cpfloat(position.y));
        hash = fold_u32(hash, hash_cpfloat(velocity.x));
        hash = fold_u32(hash, hash_cpfloat(velocity.y));
        hash = fold_u32(hash, hash_cpfloat(angle));
        hash = fold_u32(hash, hash_cpfloat(angular_velocity));
    }

    return hash;
}

static int32_t probe_position_component(int32_t index, int32_t iterations, int axis, int variant) {
    Scene scene = build_scene(variant);
    cpVect position;

    if (index < 0 || index >= 4) {
        return -1;
    }

    step_scene(&scene, iterations);
    position = cpBodyGetPosition(scene.bodies[index]);
    return (int32_t)hash_cpfloat(axis == 0 ? position.x : position.y);
}

int32_t chipmunk_hash_scene(int32_t iterations) {
    Scene scene = build_scene(0);
    step_scene(&scene, iterations);
    return (int32_t)scene_hash(&scene);
}

int32_t chipmunk_hash_scene_variant(int32_t iterations) {
    Scene scene = build_scene(1);
    step_scene(&scene, iterations);
    return (int32_t)scene_hash(&scene);
}

int32_t chipmunk_probe_body_x(int32_t index, int32_t iterations) {
    return probe_position_component(index, iterations, 0, 0);
}

int32_t chipmunk_probe_body_y(int32_t index, int32_t iterations) {
    return probe_position_component(index, iterations, 1, 0);
}

int32_t chipmunk_probe_angle(int32_t index, int32_t iterations) {
    Scene scene = build_scene(0);

    if (index < 0 || index >= 4) {
        return -1;
    }

    step_scene(&scene, iterations);
    return (int32_t)hash_cpfloat(cpBodyGetAngle(scene.bodies[index]));
}
