# frozen_string_literal: true

require "spec_helper"

describe Products::Edit::ContentController do
  let(:seller) { create(:named_user) }
  let(:product) { create(:product, user: seller) }

  before do
    sign_in seller
  end

  describe "GET edit" do
    it "renders successfully for the product owner" do
      get :edit, params: { id: product.unique_permalink }
      expect(response).to be_successful
    end

    context "with other user not owning the product" do
      let(:other_user) { create(:user) }

      before do
        sign_in other_user
      end

      it "redirects to product page" do
        get :edit, params: { id: product.unique_permalink }
        expect(response).to redirect_to(short_link_path(product))
      end
    end

    context "when the product is a bundle" do
      let(:bundle) { create(:product, :bundle) }

      it "redirects to the bundle edit page" do
        sign_in bundle.user
        get :edit, params: { id: bundle.unique_permalink }
        expect(response).to redirect_to(bundle_path(bundle.external_id))
      end
    end
  end
end
