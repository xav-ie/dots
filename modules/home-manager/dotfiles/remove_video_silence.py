import sys
import os
from moviepy.editor import *
from pydub import AudioSegment
from pydub.silence import detect_nonsilent

def remove_silence(input_video, output_video, silence_threshold=-50, min_silence_len=1000):
    # Load video
    print("Loading video...")
    video = VideoFileClip(input_video)
    # Load audio using pydub
    print("Loading audio...")
    audio_segment = AudioSegment.from_file(input_video, "mp4")
    # Detect non-silent chunks
    print("Detecting non-silent ranges...")
    non_silent_ranges = detect_nonsilent(audio_segment, min_silence_len, silence_threshold)
    # Convert non-silent chunks to time ranges and concatenate video clips
    non_silent_clips = []
    print("Gathering clips...")
    for start, end in non_silent_ranges:
        start_time = start / 1000.0
        end_time = end / 1000.0
        non_silent_clips.append(video.subclip(start_time, end_time))
    # Combine non-silent clips and export the result
    print("Concatenating clips...")
    final_video = concatenate_videoclips(non_silent_clips)
    print("Saving video...")
    final_video.write_videofile(output_video, codec="libx264", audio_codec="aac", format="matroska")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("Usage: python remove_silence.py input_video.mp4 output_video.mkv")
        sys.exit(1)

    input_video = sys.argv[1]
    output_video = sys.argv[2]

    remove_silence(input_video, output_video)
