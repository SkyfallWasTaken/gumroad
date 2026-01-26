# frozen_string_literal: true

class Products::Edit::ReceiptController < Products::Edit::BaseController
  def edit
    set_title

    render inertia: "Products/Edit/Receipt", props: all_tab_props.merge(active_tab: "receipt")
  end

  def update
    begin
      ActiveRecord::Base.transaction do
        update_receipt_settings
      end
    rescue ActiveRecord::RecordNotSaved, ActiveRecord::RecordInvalid, Link::LinkInvalid => e
      error_message = @product.errors.full_messages.first || e.message
      return handle_save_error(error_message, edit_link_receipt_path(@product.unique_permalink))
    end

    redirect_back fallback_location: edit_link_receipt_path(@product.unique_permalink),
                  notice: "Changes saved!"
  end

  private
    def update_receipt_settings
      @product.assign_attributes(product_permitted_params.slice(
        :custom_receipt,
        :custom_view_content_button_text
      ))

      @product.save!
    end
end
