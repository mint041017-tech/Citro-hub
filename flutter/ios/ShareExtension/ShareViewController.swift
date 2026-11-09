import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
  private static let appGroup = "group.com.chimu.crew"

  private let spinner = UIActivityIndicatorView(style: .large)
  private let titleLabel = UILabel()
  private let detailLabel = UILabel()
  private let actionButton = UIButton(type: .system)
  private var started = false
  private var finished = false

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.text = "正在发送到 Citro"
    titleLabel.font = .preferredFont(forTextStyle: .headline)
    titleLabel.textAlignment = .center

    detailLabel.translatesAutoresizingMaskIntoConstraints = false
    detailLabel.text = "账单识别会在 Citro 中完成"
    detailLabel.font = .preferredFont(forTextStyle: .subheadline)
    detailLabel.textColor = .secondaryLabel
    detailLabel.textAlignment = .center
    detailLabel.numberOfLines = 0

    actionButton.translatesAutoresizingMaskIntoConstraints = false
    actionButton.setTitle("取消", for: .normal)
    actionButton.addTarget(self, action: #selector(close), for: .touchUpInside)
    actionButton.isHidden = false

    let stack = UIStackView(arrangedSubviews: [
      spinner, titleLabel, detailLabel, actionButton,
    ])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.axis = .vertical
    stack.alignment = .center
    stack.spacing = 14
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
    ])
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !started else { return }
    started = true
    processSharedImage()
  }

  private func processSharedImage() {
    guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
      fail("没有收到可分享的内容")
      return
    }
    let providers = items.flatMap { $0.attachments ?? [] }
    guard
      let provider = providers.first(where: {
        $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
      })
    else {
      fail("请分享一张账单截图")
      return
    }

    provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) {
      [weak self] url, _ in
      guard let self = self, !self.finished else { return }
      guard
        let url = url,
        let data = try? Data(contentsOf: url),
        let image = UIImage(data: data),
        let jpeg = Self.prepare(image)
      else {
        DispatchQueue.main.async { self.fail("图片读取失败，请换一张截图重试") }
        return
      }
      DispatchQueue.global(qos: .userInitiated).async {
        let stored = Self.store(jpeg)
        DispatchQueue.main.async {
          guard !self.finished else { return }
          if stored {
            self.openHost()
          } else {
            self.fail("无法写入 Citro 共享目录，请重新安装 App 后重试")
          }
        }
      }
    }
  }

  private static func prepare(_ image: UIImage) -> Data? {
    let pixelWidth = image.size.width * image.scale
    let pixelHeight = image.size.height * image.scale
    let longest = max(pixelWidth, pixelHeight)
    guard longest > 0 else { return nil }
    let ratio = min(1, 1800 / longest)
    let size = CGSize(
      width: max(1, (pixelWidth * ratio).rounded()),
      height: max(1, (pixelHeight * ratio).rounded())
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    let resized = renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: size))
    }
    return resized.jpegData(compressionQuality: 0.88)
  }

  private static func store(_ data: Data) -> Bool {
    let fm = FileManager.default
    guard
      let container = fm.containerURL(
        forSecurityApplicationGroupIdentifier: ShareViewController.appGroup
      )
    else { return false }
    let name = "ledger-intake-\(Int(Date().timeIntervalSince1970 * 1000)).jpg"
    do {
      try data.write(to: container.appendingPathComponent(name), options: .atomic)
      return true
    } catch {
      return false
    }
  }

  private func openHost() {
    guard let url = URL(string: "citro://ledger/scan") else {
      showManualHint()
      return
    }
    extensionContext?.open(url) { [weak self] success in
      DispatchQueue.main.async {
        guard let self = self, !self.finished else { return }
        if success {
          self.close()
        } else {
          self.showManualHint()
        }
      }
    }
  }

  private func showManualHint() {
    spinner.stopAnimating()
    titleLabel.text = "已发送到 Citro"
    detailLabel.text = "请打开 Citro，账单会自动进入「记一笔」。"
    actionButton.setTitle("完成", for: .normal)
    actionButton.isHidden = false
  }

  private func fail(_ message: String) {
    spinner.stopAnimating()
    titleLabel.text = "发送失败"
    detailLabel.text = message
    actionButton.setTitle("关闭", for: .normal)
    actionButton.isHidden = false
  }

  @objc private func close() {
    guard !finished else { return }
    finished = true
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}