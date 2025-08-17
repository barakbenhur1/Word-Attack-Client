# 🧠 Wordle AI Models for CoreML

This repository contains two fine-tuned GPT-2 models designed to guess 5-letter words in the style of Wordle, supporting both **English** and **Hebrew**. Each model is exported and optimized for use on Apple devices via CoreML.

## 📦 Structure

WordleModels/
├── English/
│ ├── WordleGPT.mlmodelc/ # Compiled CoreML model
│ └── tokenizer/ # Tokenizer files
│ ├── vocab.json
│ └── merges.txt
├── Hebrew/
│ ├── WordleGPT.mlmodelc/
│ └── tokenizer/
│ ├── vocab.json
│ └── merges.txt

## 🧰 Requirements

- iOS 15+ or macOS 12+ (recommended)
- CoreML runtime support
- Swift 5.5+
- Tokenizer loader (`Tokenizer.swift`) – provided in this repo
- [CoreMLTools](https://github.com/apple/coremltools) (for advanced model compilation)

## ⚙️ Usage

1. Copy `WordleGPT.mlmodelc` and `tokenizer/` into your Xcode project.
2. Use the provided `Tokenizer.swift` to encode/decode strings to token IDs.
3. Run inference using `MLModel` or `WordleGPT().prediction(...)` API.

## 🗣 Languages Supported

- 🇬🇧 English: Trained on the official Wordle word list (excluding banned words)
- 🇮🇱 Hebrew: Trained on a curated list of 5-letter Hebrew words

## 🚀 Coming Soon

- `.mlpackage` versions for model inspection
- Swift Playground demo
- Performance benchmarks
- Auto-suggestions and game integration code

## 📝 License

MIT License

