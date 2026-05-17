# Objections And Answers

## We already have geofencing in the autopilot.

Good. Edge is not trying to replace that. The pilot asks whether planner/agent commands can be independently evaluated, denied, audited, replayed, and reported before they reach the control bridge.

## SITL is not real flight.

Correct. SITL is simulator evidence. The value is reproducible policy and evidence workflow testing before deeper integration. It should not be presented as aircraft validation.

## Does this certify us?

No. Edge produces customer-evaluation evidence and limitations. It does not certify, approve, or replace regulatory work.

## Can this replace our safety system?

No. It can be an additional policy and evidence layer in supported evaluation scenarios. Your safety system and process remain authoritative.

## We do not use AI agents yet.

The same question applies to mission planners, automation scripts, or autonomy services: what commands can software issue, and how do you prove unsafe commands were blocked?

## We use custom MAVLink messages.

That can still be a fit if one pilot workflow has a bounded command surface. Custom message mapping must be explicit, and unsupported commands stay out of scope until reviewed.

## We use ROS2.

The technical validation call should map where ROS2 turns intent into command messages. A pilot may focus on the bridge boundary rather than the whole ROS graph.

## We cannot share our stack.

We can start from fake adapter scenarios, public interface descriptions, or redacted command examples. If we cannot map one command workflow, it is not ready for pilot.

## We need hardware support.

The first pilot should prove local policy and evidence workflows before any hardware discussion. Bench-preparation can review no-actuation behavior, not operate aircraft.

## We need BVLOS approval.

Edge cannot provide that. It may help produce internal evaluation evidence, but approval work remains separate.

## We are too early.

If no planner command surface or simulator exists yet, it may be too early. If you are designing that boundary now, a short design-partner evaluation may still help.

## We are too regulated.

Regulated teams often need better traceability, but the scope must be explicit: evaluation artifacts, limitations, and no approval claim.

## What does this prove?

It can prove how Edge behaved on supported local scenarios: input, state, rule, decision, replay integrity, red-team result, and limitations.

## Why not just use PX4/ArduPilot failsafes?

You should use them. Edge focuses on the planner/agent command boundary, auditability, replay, data guard, red-team scenarios, and safety-case evidence around supported evaluation workflows.
