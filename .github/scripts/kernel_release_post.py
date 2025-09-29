#!/usr/bin/env python
import telebot
import os
import sys

def getConfig(config_name: str):
    """Get configuration from environment variables."""
    value = os.getenv(config_name)
    if not value:
        print(f"Error: {config_name} is not set.")
        exit(1)
    return value

# Get configuration
try:
    BOT_TOKEN = getConfig("TELEGRAM_BOT_TOKEN")
    CHAT_ID = getConfig("TELEGRAM_CHANNEL_ID")
    TOPIC_ID = getConfig("TELEGRAM_TOPIC_ID")
    RELEASE_TAG = getConfig("RELEASE_TAG")
    RELEASE_URL = getConfig("RELEASE_URL")
    RELEASE_BODY = os.getenv("RELEASE_BODY", "No changelog provided.")
except SystemExit:
    exit(1)

BANNER_PATH = "assets/release-banner.jpg"

# Initialize bot with HTML parse mode
bot = telebot.TeleBot(BOT_TOKEN, parse_mode="HTML")

def generate_kernel_post_message():
    """Generate the kernel release message."""
    msg = f"🔥⚡️ FrEeRuNnErKeRnEl-{RELEASE_TAG}⚡️🔥\n"
    msg += "Samsung Galaxy S10 Series, Samsung Galaxy Note 10 Series & Samsung Galaxy F62\n"
    msg += f"<a href='{RELEASE_URL}'>Kernel release</a>\n"
    msg += "<a href='https://github.com/ProjectMatrixx-exynos9820/android_kernel_samsung_exynos9820'>Kernel Source</a>\n"
    msg += "<a href='https://github.com/KernelSU-Next/KernelSU-Next/releases'>KernelSU-Next Manager</a>\n"

    msg += "Changelog:\n"
    msg += f"{RELEASE_BODY}\n"

    msg += "Note: This kernel will only work on AOSP ONLY NOT ONEUI!\n"
    msg += "Compatible with Android 15 & 16\n"

    msg += "Thanks: \n"
    msg += "<a href='http://t.me/linux4'>linux4</a> for kernel\n"
    msg += "<a href='http://t.me/rifsxd'>rifsxd</a> for kernelsu-next\n"
    msg += "<a href='http://t.me/sidex15'>sidex15</a> for susfs4ksu\n"
    msg += "All testers"

    return msg

def send_kernel_post():
    """Send the kernel release post to Telegram."""
    try:
        message = generate_kernel_post_message()

        # Check if banner exists
        if not os.path.exists(BANNER_PATH):
            print(f"Warning: Banner not found at {BANNER_PATH}")
            # Send text-only message if banner is missing
            bot.send_message(
                chat_id=CHAT_ID,
                message_thread_id=TOPIC_ID,
                text=message
            )
        else:
            # Send with banner
            with open(BANNER_PATH, "rb") as banner:
                bot.send_photo(
                    chat_id=CHAT_ID,
                    message_thread_id=TOPIC_ID,
                    photo=banner,
                    caption=message
                )

        print(f"Successfully sent kernel release post to chat ID: {CHAT_ID}, topic: {TOPIC_ID}")

    except Exception as e:
        print(f"Failed to send post. Error: {e}")
        exit(1)

if __name__ == "__main__":
    print(f"Processing kernel release: {RELEASE_TAG}")
    send_kernel_post()
    print("Kernel release post completed successfully!")
