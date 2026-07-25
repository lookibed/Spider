#include <stdint.h>

#include "chipmunk/chipmunk.h"

void shim_reset_heap(void);

typedef struct Scene {
    cpSpace *space;
    cpBody *bodies[4];
} Scene;

typedef struct MemoryNode {
    cpFloat x;
    cpFloat y;
    cpFloat vx;
    cpFloat vy;
    int32_t next;
} MemoryNode;

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

static Scene build_scene(int mode) {
    Scene scene;

    shim_reset_heap();

    scene.space = cpSpaceNew();
    scene.bodies[0] = 0;
    scene.bodies[1] = 0;
    scene.bodies[2] = 0;
    scene.bodies[3] = 0;

    cpSpaceSetIterations(scene.space, 20);
    cpSpaceSetGravity(scene.space, cpv(0.0, -120.0));
    cpSpaceSetDamping(scene.space, 0.997);
    cpSpaceSetSleepTimeThreshold(scene.space, INFINITY);
    cpSpaceSetCollisionSlop(scene.space, 0.05);

    if (mode >= 1) {
        cpShape *ground = cpSegmentShapeNew(cpSpaceGetStaticBody(scene.space), cpv(-40.0, -12.0), cpv(40.0, -12.0), 0.0);
        cpShape *slope = cpSegmentShapeNew(cpSpaceGetStaticBody(scene.space), cpv(10.0, -8.0), cpv(28.0, -1.0), 0.0);

        cpShapeSetFriction(ground, 1.0);
        cpShapeSetElasticity(ground, 0.0);
        cpShapeSetFriction(slope, 0.9);
        cpShapeSetElasticity(slope, 0.0);

        cpSpaceAddShape(scene.space, ground);
        cpSpaceAddShape(scene.space, slope);
    }

    if (mode == 0) {
        cpBody *body0 = cpBodyNew(1.5, cpMomentForBox(1.5, 2.4, 2.0));
        cpBody *body1 = cpBodyNew(1.0, cpMomentForCircle(1.0, 0.0, 1.2, cpvzero));
        cpBody *body2 = cpBodyNew(1.75, cpMomentForBox(1.75, 2.0, 2.0));
        cpBody *body3 = cpBodyNew(1.15, cpMomentForCircle(1.15, 0.0, 1.0, cpvzero));

        cpBodySetPosition(body0, cpv(-8.0, 4.0));
        cpBodySetPosition(body1, cpv(-2.5, 10.0));
        cpBodySetPosition(body2, cpv(3.0, 15.0));
        cpBodySetPosition(body3, cpv(8.0, 20.0));
        cpBodySetAngle(body0, 0.15);
        cpBodySetAngle(body2, -0.2);

        cpSpaceAddBody(scene.space, body0);
        cpSpaceAddBody(scene.space, body1);
        cpSpaceAddBody(scene.space, body2);
        cpSpaceAddBody(scene.space, body3);

        scene.bodies[0] = body0;
        scene.bodies[1] = body1;
        scene.bodies[2] = body2;
        scene.bodies[3] = body3;
    } else {
        add_box(&scene, 0, 1.5, 2.4, 2.0, cpv(-8.0, 4.0));
        add_circle(&scene, 1, 1.0, 1.2, cpv(-2.5, 10.0));
        add_box(&scene, 2, 1.75, 2.0, 2.0, cpv(3.0, 15.0));
        add_circle(&scene, 3, 1.15, 1.0, cpv(8.0, 20.0));
        cpBodySetAngle(scene.bodies[0], 0.15);
        cpBodySetAngle(scene.bodies[2], -0.2);
    }

    if (mode >= 2) {
        cpConstraint *pivot = cpPivotJointNew(cpSpaceGetStaticBody(scene.space), scene.bodies[0], cpv(-8.0, 6.0));
        cpConstraint *spring = cpDampedSpringNew(scene.bodies[1], scene.bodies[2], cpvzero, cpvzero, 6.5, 140.0, 4.0);
        cpConstraint *slide = cpSlideJointNew(scene.bodies[2], scene.bodies[3], cpvzero, cpvzero, 2.5, 6.0);

        cpConstraintSetMaxForce(pivot, 8000.0);
        cpConstraintSetMaxForce(spring, 12000.0);
        cpConstraintSetMaxForce(slide, 10000.0);

        cpSpaceAddConstraint(scene.space, pivot);
        cpSpaceAddConstraint(scene.space, spring);
        cpSpaceAddConstraint(scene.space, slide);
    }

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

int32_t profile_memory_walk(int32_t iterations) {
    MemoryNode *nodes = (MemoryNode *)calloc(256, sizeof(MemoryNode));
    uint32_t hash = 0xC0FFEE11U;
    int32_t i = 0;
    int32_t cursor = 0;

    for (i = 0; i < 256; i++) {
        nodes[i].x = (cpFloat)(i * 0.125);
        nodes[i].y = (cpFloat)(i * 0.25);
        nodes[i].vx = (cpFloat)(i * 0.03125);
        nodes[i].vy = (cpFloat)(i * -0.015625);
        nodes[i].next = (i * 73 + 19) & 255;
    }

    for (i = 0; i < iterations; i++) {
        int step = 0;
        for (step = 0; step < 256; step++) {
            MemoryNode *node = &nodes[cursor];
            node->x = node->x + node->vx;
            node->y = node->y + node->vy;
            node->vx = node->vx + (node->y * 0.0009765625);
            node->vy = node->vy - (node->x * 0.00048828125);
            hash = fold_u32(hash, hash_cpfloat(node->x));
            cursor = node->next;
        }
    }

    return (int32_t)hash;
}

int32_t profile_math_shim(int32_t iterations) {
    cpFloat x = 0.875;
    cpFloat y = 1.125;
    uint32_t hash = 0x13572468U;
    int32_t i = 0;

    for (i = 0; i < iterations; i++) {
        cpFloat angle = ((cpFloat)(i & 255) * 0.03125) - 2.0;
        cpFloat trig = cpfsin(angle) + cpfcos(angle * 0.5);
        cpFloat root = cpfsqrt(cpfabs(x * y) + 0.125);
        cpFloat arc = cpfacos(cpfclamp(trig * 0.25, -1.0, 1.0));
        cpFloat polar = cpfatan2(y + 0.25, x - 0.125);
        cpFloat power = cpfpow(root + 1.0, 1.125);
        cpFloat expo = cpfexp((trig * 0.125) - 0.05);

        x = root + arc + polar;
        y = power / (expo + 1.0);
        hash = fold_u32(hash, hash_cpfloat(x));
        hash = fold_u32(hash, hash_cpfloat(y));
    }

    return (int32_t)hash;
}

int32_t profile_branch_state(int32_t iterations) {
    cpFloat state[32];
    uint32_t hash = 0x2468ACE1U;
    int32_t i = 0;
    int32_t j = 0;

    for (j = 0; j < 32; j++) {
        state[j] = (cpFloat)(j - 16) * 0.25;
    }

    for (i = 0; i < iterations; i++) {
        for (j = 0; j < 32; j++) {
            cpFloat value = state[j];
            cpFloat neighbor = state[(j + 7) & 31];

            if ((i + j) & 1) {
                value = value * 1.03125 + neighbor * 0.125;
            } else if ((i + j) % 3 == 0) {
                value = value - neighbor * 0.375;
            } else {
                value = value + neighbor * 0.0625 + (cpFloat)(j & 3);
            }

            if (value > 8.0) {
                value = value * 0.5;
            } else if (value < -8.0) {
                value = value * -0.25;
            }

            state[j] = value;
            hash = fold_u32(hash, hash_cpfloat(value));
        }
    }

    return (int32_t)hash;
}

int32_t profile_space_freefall(int32_t iterations) {
    Scene scene = build_scene(0);
    step_scene(&scene, iterations);
    return (int32_t)scene_hash(&scene);
}

int32_t profile_space_collision(int32_t iterations) {
    Scene scene = build_scene(1);
    step_scene(&scene, iterations);
    return (int32_t)scene_hash(&scene);
}

int32_t profile_space_full(int32_t iterations) {
    Scene scene = build_scene(2);
    step_scene(&scene, iterations);
    return (int32_t)scene_hash(&scene);
}
