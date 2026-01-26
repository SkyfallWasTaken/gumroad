# frozen_string_literal: true

class ProductPresenter::Edit::ReceiptTabProps
  attr_reader :product, :pundit_user

  def initialize(product:, pundit_user:)
    @product = product
    @pundit_user = pundit_user
  end

  def props
    {
      product: product_props,
    }
  end

  private
    def product_props
      {
        custom_receipt_text: product.custom_receipt_text,
        custom_receipt_text_max_length: Product::Validations::MAX_CUSTOM_RECEIPT_TEXT_LENGTH,
        custom_view_content_button_text: product.custom_view_content_button_text,
        custom_view_content_button_text_max_length: Product::Validations::MAX_VIEW_CONTENT_BUTTON_TEXT_LENGTH,
      }
    end
end
