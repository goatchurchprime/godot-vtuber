#!/usr/bin/env python3
"""Webcam MediaPipe Tasks bridge for the Godot UDP tracking adapter."""

from __future__ import annotations

import argparse
import json
import math
import socket
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=7007)
    parser.add_argument("--camera", type=int, default=0)
    parser.add_argument("--synthetic", action="store_true", help="exercise deployment without MediaPipe")
    parser.add_argument("--preview", action="store_true", help="show MediaPipe's landmark overlay; Q or Esc exits")
    parser.add_argument("--godot-preview-fps", type=float, default=10.0, help="annotated preview rate sent to Godot; zero disables")
    parser.add_argument("--max-frames", type=int, default=0, help="exit after N frames; zero runs continuously")
    parser.add_argument("--status-every", type=int, default=300, help="report throughput every N frames")
    args = parser.parse_args()
    destination = (args.host, args.port)
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    if args.synthetic:
        print(f"tracking bridge: synthetic -> udp://{args.host}:{args.port}", file=sys.stderr, flush=True)
        frame_count = 0
        while True:
            now = time.monotonic()
            send(sender, destination, now, [4 * math.sin(now), 10 * math.sin(now * .7), 0], [.03 * math.sin(now * .4), 0, 0])
            frame_count += 1
            if args.max_frames and frame_count >= args.max_frames:
                return 0
            time.sleep(1 / 30)

    try:
        import cv2
        import mediapipe as mp
    except ImportError as exc:
        raise SystemExit("Install opencv-python and mediapipe, or use --synthetic") from exc
    # Force V4L2 on Linux: backend auto-probing can stall even when the camera
    # node is healthy, which obscures deployment failures.
    capture = cv2.VideoCapture(args.camera, cv2.CAP_V4L2)
    if not capture.isOpened():
        raise SystemExit(f"camera {args.camera} did not open")
    capture.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    capture.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    capture.set(cv2.CAP_PROP_BUFFERSIZE, 1)
    print(f"tracking bridge: camera {args.camera} -> udp://{args.host}:{args.port}", file=sys.stderr, flush=True)
    pose = mp.solutions.pose.Pose(model_complexity=1)
    face = mp.solutions.face_mesh.FaceMesh(max_num_faces=1, refine_landmarks=True)
    frame_count = 0
    started = time.monotonic()
    last_godot_preview = 0.0
    try:
        while True:
            ok, image = capture.read()
            if not ok:
                raise SystemExit("camera frame read failed")
            rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
            pose_result = pose.process(rgb)
            face_result = face.process(rgb)
            head = estimate_head(face_result)
            shoulders = estimate_shoulders(pose_result)
            send(sender, destination, time.monotonic(), head, shoulders)
            annotated = None
            now = time.monotonic()
            preview_due = args.godot_preview_fps > 0 and now - last_godot_preview >= 1.0 / args.godot_preview_fps
            if args.preview or preview_due:
                annotated = annotate_preview(cv2, mp, image, pose_result, face_result, head, shoulders, frame_count)
            if preview_due:
                send_preview(cv2, sender, destination, annotated)
                last_godot_preview = now
            if args.preview and annotated is not None:
                cv2.imshow("MediaPipe tracking boundary (data sent to Godot)", annotated)
                key = cv2.waitKey(1) & 0xFF
                if key in (ord("q"), 27):
                    return 0
            frame_count += 1
            if args.status_every > 0 and frame_count % args.status_every == 0:
                elapsed = time.monotonic() - started
                print(f"tracking bridge: {frame_count} frames, {frame_count / elapsed:.1f} fps", file=sys.stderr, flush=True)
            if args.max_frames and frame_count >= args.max_frames:
                return 0
    finally:
        capture.release()
        if args.preview:
            cv2.destroyAllWindows()


def annotate_preview(cv2, mp, image, pose_result, face_result, head, shoulders, frame_count):
    """Render MediaPipe's own topology plus the exact values sent to Godot."""
    image = image.copy()
    drawing = mp.solutions.drawing_utils
    styles = mp.solutions.drawing_styles
    if pose_result.pose_landmarks:
        drawing.draw_landmarks(
            image,
            pose_result.pose_landmarks,
            mp.solutions.pose.POSE_CONNECTIONS,
            landmark_drawing_spec=styles.get_default_pose_landmarks_style(),
        )
    if face_result.multi_face_landmarks:
        drawing.draw_landmarks(
            image,
            face_result.multi_face_landmarks[0],
            mp.solutions.face_mesh.FACEMESH_CONTOURS,
            landmark_drawing_spec=None,
            connection_drawing_spec=styles.get_default_face_mesh_contours_style(),
        )
    lines = (
        f"sent head pitch/yaw/roll: {head[0]:+.1f} {head[1]:+.1f} {head[2]:+.1f} deg",
        f"sent shoulder xyz: {shoulders[0]:+.3f} {shoulders[1]:+.3f} {shoulders[2]:+.3f}",
        f"frame {frame_count + 1} | Q/Esc closes preview and bridge",
    )
    for row, text in enumerate(lines):
        cv2.putText(image, text, (12, 28 + row * 26), cv2.FONT_HERSHEY_SIMPLEX, .58, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(image, text, (12, 28 + row * 26), cv2.FONT_HERSHEY_SIMPLEX, .58, (80, 255, 120), 1, cv2.LINE_AA)
    return image


def send_preview(cv2, sender, destination, image) -> None:
    """Send one self-contained, lossy preview datagram; pose data stays separate."""
    scaled = cv2.resize(image, (480, 360), interpolation=cv2.INTER_AREA)
    quality = 65
    while quality >= 35:
        ok, encoded = cv2.imencode(".jpg", scaled, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok and encoded.size <= 60_000:
            sender.sendto(b"VTPJ" + encoded.tobytes(), destination)
            return
        quality -= 10
    print("tracking bridge: preview JPEG exceeded UDP budget", file=sys.stderr, flush=True)


def estimate_head(result) -> list[float]:
    if not result.multi_face_landmarks:
        return [0.0, 0.0, 0.0]
    points = result.multi_face_landmarks[0].landmark
    nose, left, right = points[1], points[234], points[454]
    yaw = (nose.x - (left.x + right.x) * .5) * 100.0
    roll = math.degrees(math.atan2(right.y - left.y, right.x - left.x))
    pitch = (nose.y - (left.y + right.y) * .5) * 70.0
    return [pitch, yaw, roll]


def estimate_shoulders(result) -> list[float]:
    if not result.pose_landmarks:
        return [0.0, 0.0, 0.0]
    points = result.pose_landmarks.landmark
    left, right = points[11], points[12]
    return [(.5 - (left.x + right.x) * .5) * .5, .5 - (left.y + right.y) * .5, (left.z + right.z) * .5]


def send(sender, destination, now, head, shoulders) -> None:
    packet = {
        "schema_version": 1,
        "capture_timestamp_usec": int(now * 1_000_000),
        "landmarks": {"head_rotation_degrees": head, "shoulder_center": shoulders},
        "confidence": {"face": 1.0, "pose": 1.0},
        "face_blend_shapes": {},
    }
    sender.sendto(json.dumps(packet, separators=(",", ":")).encode(), destination)


if __name__ == "__main__":
    raise SystemExit(main())
